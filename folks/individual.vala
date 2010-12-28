/*
 * Copyright (C) 2010 Collabora Ltd.
 *
 * This library is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Authors:
 *       Travis Reitter <travis.reitter@collabora.co.uk>
 */

using Gee;
using GLib;

/**
 * Trust level for an {@link Individual} for use in the UI.
 *
 * @since 0.1.15
 */
public enum Folks.TrustLevel
{
  /**
   * The {@link Individual}'s {@link Persona}s aren't trusted at all.
   *
   * This is the trust level for an {@link Individual} which contains one or
   * more {@link Persona}s which cannot be guaranteed to be the same
   * {@link Persona}s as were originally linked together.
   *
   * For example, an {@link Individual} containing a link-local XMPP
   * {@link Persona} would have this trust level, since someone else could
   * easily spoof the link-local XMPP {@link Persona}'s identity.
   *
   * @since 0.1.15
   */
  NONE,

  /**
   * The {@link Individual}'s {@link Persona}s are trusted.
   *
   * This trust level is for {@link Individual}s where it can be guaranteed
   * that all the {@link Persona}s are the same ones as when they were
   * originally linked together.
   *
   * Note that this doesn't guarantee that the user who behind each
   * {@link Persona} is who they claim to be.
   *
   * @since 0.1.15
   */
  PERSONAS
}

/**
 * A physical person, aggregated from the various {@link Persona}s the person
 * might have, such as their different IM addresses or vCard entries.
 */
public class Folks.Individual : Object,
    Aliasable,
    Favouritable,
    Groupable,
    HasAvatar,
    HasPresence,
    IMable
{
  private bool _is_favourite;
  private string _alias;
  private HashTable<string, bool> _groups;
  /* These two data structures should store exactly the same set of Personas:
   * the Personas contained in this Individual. The HashSet is used for fast
   * lookups, whereas the List is used for iteration.
   * The Individual's references to its Personas are kept by the HashSet;
   * since the List contains the same set of Personas, it doesn't need an
   * extra reference (and due to bgo#624249, this is a good thing). */
  private GLib.List<unowned Persona> _persona_list;
  private HashSet<Persona> _persona_set;
  /* Mapping from PersonaStore -> number of Personas from that store contained
   * in this Individual. There shouldn't be any entries with a number < 1.
   * This is used for working out when to disconnect from store signals. */
  private HashMap<PersonaStore, uint> _stores;
  /* The number of Personas in this Individual which have
   * Persona.is_user == true. Iff this is > 0, Individual.is_user == true. */
  private uint _persona_user_count = 0;
  private HashTable<string, GenericArray<string>> _im_addresses;

  /**
   * The trust level of the Individual.
   *
   * This specifies how far the Individual can be trusted to be who it claims
   * to be. See the descriptions for the elements of {@link TrustLevel}.
   *
   * Clients should ''not'' allow linking of Individuals who have a trust level
   * of {@link TrustLevel.NONE}.
   *
   * @since 0.1.15
   */
  public TrustLevel trust_level { get; private set; }

  /**
   * {@inheritDoc}
   */
  public File avatar { get; private set; }

  /**
   * {@inheritDoc}
   */
  public Folks.PresenceType presence_type { get; private set; }

  /**
   * {@inheritDoc}
   */
  public string presence_message { get; private set; }

  /**
   * Whether the Individual is the user.
   *
   * Iff the Individual represents the user (the person who owns the
   * account in the backend for each {@link Persona} in the Individual)
   * this is `true`.
   *
   * It is //not// guaranteed that every {@link Persona} in the Individual has
   * its {@link Persona.is_user} set to the same value as the Individual. For
   * example, the user could own two Telepathy accounts, and have added the
   * other account as a contact in each account. The accounts will expose a
   * {@link Persona} for the user (which will have {@link Persona.is_user} set
   * to `true`) //and// a {@link Persona} for the contact for the other account
   * (which will have {@link Persona.is_user} set to `false`).
   *
   * It is guaranteed that iff this property is set to `true` on an Individual,
   * there will be at least one {@link Persona} in the Individual with its
   * {@link Persona.is_user} set to `true`.
   *
   * It is guaranteed that there will only ever be one Individual with this
   * property set to `true`.
   *
   * @since 0.3.0
   */
  public bool is_user { get; private set; }

  /**
   * A unique identifier for the Individual.
   *
   * This uniquely identifies the Individual, and persists across
   * {@link IndividualAggregator} instances.
   *
   * FIXME: Will this.id actually be the persistent ID for storage?
   */
  public string id { get; private set; }

  /**
   * Emitted when the last of the Individual's {@link Persona}s has been
   * removed.
   *
   * At this point, the Individual is invalid, so any client referencing it
   * should unreference it and remove it from their UI.
   *
   * @param replacement_individual the individual which has replaced this one
   * due to linking, or `null` if this individual was removed for another reason
   * @since 0.1.13
   */
  public signal void removed (Individual? replacement_individual);

  /**
   * {@inheritDoc}
   */
  public string alias
    {
      get { return this._alias; }

      set
        {
          if (this._alias == value)
            return;

          this._alias = value;

          debug ("Setting alias of individual '%s' to '%s'…", this.id, value);

          /* First, try to write it to only the writeable Personas… */
          bool alias_changed = false;
          this._persona_list.foreach ((p) =>
            {
              if (p is Aliasable && ((Persona) p).store.is_writeable == true)
                {
                  debug ("    written to writeable persona '%s'",
                      ((Persona) p).uid);
                  ((Aliasable) p).alias = value;
                  alias_changed = true;
                }
            });

          /* …but if there are no writeable Personas, we have to fall back to
           * writing it to every Persona. */
          if (alias_changed == false)
            {
              this._persona_list.foreach ((p) =>
                {
                  if (p is Aliasable)
                    {
                      debug ("    written to non-writeable persona '%s'",
                          ((Persona) p).uid);
                      ((Aliasable) p).alias = value;
                    }
                });
            }
        }
    }

  /**
   * Whether this Individual is a user-defined favourite.
   *
   * This property is `true` if any of this Individual's {@link Persona}s are
   * favourites).
   */
  public bool is_favourite
    {
      get { return this._is_favourite; }

      set
        {
          if (this._is_favourite == value)
            return;

          debug ("Setting '%s' favourite status to %s", this.id,
              value ? "TRUE" : "FALSE");

          this._is_favourite = value;
          this._persona_list.foreach ((p) =>
            {
              if (p is Favouritable)
                {
                  SignalHandler.block_by_func (p,
                      (void*) this._notify_is_favourite_cb, this);
                  ((Favouritable) p).is_favourite = value;
                  SignalHandler.unblock_by_func (p,
                      (void*) this._notify_is_favourite_cb, this);
                }
            });
        }
    }

  /**
   * {@inheritDoc}
   */
  public HashTable<string, bool> groups
    {
      get { return this._groups; }

      set
        {
          this._groups = value;
          this._persona_list.foreach ((p) =>
            {
              if (p is Groupable && ((Persona) p).store.is_writeable == true)
                ((Groupable) p).groups = value;
            });
        }
    }

  /**
   * {@inheritDoc}
   */
  public HashTable<string, GenericArray<string>> im_addresses
    {
      get { return this._im_addresses; }
      private set {}
    }

  /**
   * The set of {@link Persona}s encapsulated by this Individual.
   *
   * Changing the set of personas may cause updates to the aggregated properties
   * provided by the Individual, resulting in property notifications for them.
   *
   * Changing the set of personas will not cause permanent linking/unlinking of
   * the added/removed personas to/from this Individual. To do that, call
   * {@link IndividualAggregator.link_personas} or
   * {@link IndividualAggregator.unlink_individual}, which will ensure the link
   * changes are written to the appropriate backend.
   */
  public GLib.List<Persona> personas
    {
      get { return this._persona_list; }
      set { this._set_personas (value, null); }
    }

  /**
   * Emitted when one or more {@link Persona}s are added to or removed from
   * the Individual.
   *
   * @param added a list of {@link Persona}s which have been added
   * @param removed a list of {@link Persona}s which have been removed
   *
   * @since 0.1.15
   */
  public signal void personas_changed (GLib.List<Persona>? added,
      GLib.List<Persona>? removed);

  private void _notify_alias_cb (Object obj, ParamSpec ps)
    {
      this._update_alias ();
    }

  private void _notify_avatar_cb (Object obj, ParamSpec ps)
    {
      this._update_avatar ();
    }

  private void _persona_group_changed_cb (string group, bool is_member)
    {
      this._update_groups ();
    }

  /**
   * Add or remove the Individual from the specified group.
   *
   * If `is_member` is `true`, the Individual will be added to the `group`. If
   * it is `false`, they will be removed from the `group`.
   *
   * The group membership change will propagate to every {@link Persona} in
   * the Individual.
   *
   * @param group a freeform group identifier
   * @param is_member whether the Individual should be a member of the group
   * @since 0.1.11
   */
  public async void change_group (string group, bool is_member)
    {
      this._persona_list.foreach ((p) =>
        {
          if (p is Groupable)
            ((Groupable) p).change_group.begin (group, is_member);
        });

      /* don't notify, since it hasn't happened in the persona backing stores
       * yet; react to that directly */
    }

  private void _notify_presence_cb (Object obj, ParamSpec ps)
    {
      this._update_presence ();
    }

  private void _notify_im_addresses_cb (Object obj, ParamSpec ps)
    {
      this._update_im_addresses ();
    }

  private void _notify_is_favourite_cb (Object obj, ParamSpec ps)
    {
      this._update_is_favourite ();
    }

  /**
   * Create a new Individual.
   *
   * The Individual can optionally be seeded with the {@link Persona}s in
   * `personas`. Otherwise, it will have to have personas added using the
   * {@link Folks.Individual.personas} property after construction.
   *
   * @param personas a list of {@link Persona}s to initialise the
   * {@link Individual} with, or `null`
   * @return a new Individual
   */
  public Individual (GLib.List<Persona>? personas)
    {
      this._im_addresses =
          new HashTable<string, GenericArray<string>> (str_hash, str_equal);
      this._persona_set = new HashSet<Persona> (null, null);
      this._stores = new HashMap<PersonaStore, uint> (null, null);
      this.personas = personas;
    }

  private void _store_removed_cb (PersonaStore store)
    {
      GLib.List<Persona> removed_personas = null;
      Iterator<Persona> iter = this._persona_set.iterator ();
      while (iter.next ())
        {
          Persona persona = iter.get ();

          removed_personas.prepend (persona);
          this._persona_list.remove (persona);
          iter.remove ();
        }

      if (removed_personas != null)
        this.personas_changed (null, removed_personas);

      if (store != null)
        this._stores.unset (store);

      if (this._persona_set.size < 1)
        {
          this.removed (null);
          return;
        }

      this._update_fields ();
    }

  private void _store_personas_changed_cb (PersonaStore store,
      GLib.List<Persona>? added,
      GLib.List<Persona>? removed,
      string? message,
      Persona? actor,
      Groupable.ChangeReason reason)
    {
      GLib.List<Persona> removed_personas = null;
      removed.foreach ((data) =>
        {
          unowned Persona p = (Persona) data;

          if (this._persona_set.remove (p))
            {
              removed_personas.prepend (p);
              this._persona_list.remove (p);
            }
        });

      if (removed_personas != null)
        this.personas_changed (null, removed_personas);

      if (this._persona_set.size < 1)
        {
          this.removed (null);
          return;
        }

      this._update_fields ();
    }

  private void _update_fields ()
    {
      this._update_groups ();
      this._update_presence ();
      this._update_is_favourite ();
      this._update_avatar ();
      this._update_alias ();
      this._update_trust_level ();
      this._update_im_addresses ();
    }

  private void _update_groups ()
    {
      var new_groups = new HashTable<string, bool> (str_hash, str_equal);

      /* this._groups is null during initial construction */
      if (this._groups == null)
        this._groups = new HashTable<string, bool> (str_hash, str_equal);

      /* FIXME: this should partition the personas by store (maybe we should
       * keep that mapping in general in this class), and execute
       * "groups-changed" on the store (with the set of personas), to allow the
       * back-end to optimize it (like Telepathy will for MembersChanged for the
       * groups channel list) */
      this._persona_list.foreach ((p) =>
        {
          if (p is Groupable)
            {
              unowned Groupable persona = (Groupable) p;

              persona.groups.foreach ((k, v) =>
                {
                  new_groups.insert ((string) k, true);
                });
            }
        });

      new_groups.foreach ((k, v) =>
        {
          var group = (string) k;
          if (this._groups.lookup (group) != true)
            {
              this._groups.insert (group, true);
              this._groups.foreach ((k, v) =>
                {
                  var g = (string) k;
                  debug ("   %s", g);
                });

              this.group_changed (group, true);
            }
        });

      /* buffer the removals, so we don't remove while iterating */
      var removes = new GLib.List<string> ();
      this._groups.foreach ((k, v) =>
        {
          var group = (string) k;
          if (new_groups.lookup (group) != true)
            removes.prepend (group);
        });

      removes.foreach ((l) =>
        {
          var group = (string) l;
          this._groups.remove (group);
          this.group_changed (group, false);
        });
    }

  private void _update_presence ()
    {
      var presence_message = "";
      var presence_type = Folks.PresenceType.UNSET;

      /* Choose the most available presence from our personas */
      this._persona_list.foreach ((p) =>
        {
          if (p is HasPresence)
            {
              unowned HasPresence presence = (HasPresence) p;

              if (HasPresence.typecmp (presence.presence_type,
                  presence_type) > 0)
                {
                  presence_type = presence.presence_type;
                  presence_message = presence.presence_message;
                }
            }
        });

      if (presence_message == null)
        presence_message = "";

      /* only notify if the value has changed */
      if (this.presence_message != presence_message)
        this.presence_message = presence_message;

      if (this.presence_type != presence_type)
        this.presence_type = presence_type;
    }

  private void _update_is_favourite ()
    {
      bool favourite = false;

      debug ("Running _update_is_favourite() on '%s'", this.id);

      this._persona_list.foreach ((p) =>
        {
          if (favourite == false && p is Favouritable)
            {
              favourite = ((Favouritable) p).is_favourite;
              if (favourite == true)
                return;
            }
        });

      /* Only notify if the value has changed. We have to set the private member
       * and notify manually, or we'd end up propagating the new favourite
       * status back down to all our Personas. */
      if (this._is_favourite != favourite)
        {
          this._is_favourite = favourite;
          this.notify_property ("is-favourite");
        }
    }

  private void _update_alias ()
    {
      string alias = null;
      bool alias_is_display_id = false;

      debug ("Updating alias for individual '%s'", this.id);

      /* Search for an alias from a writeable Persona, and use it as our first
       * choice if it's non-empty, since that's where the user-set alias is
       * stored. */
      foreach (Persona p in this._persona_list)
        {
          if (p is Aliasable && p.store.is_writeable == true)
            {
              unowned Aliasable a = (Aliasable) p;

              if (a.alias != null && a.alias.strip () != "")
                {
                  alias = a.alias;
                  break;
                }
            }
        }

      debug ("    got alias '%s' from writeable personas", alias);

      /* Since we can't find a non-empty alias from a writeable backend, try
       * the aliases from other personas. Use a non-empty alias which isn't
       * equal to the persona's display ID as our preference. If we can't find
       * one of those, fall back to one which is equal to the display ID. */
      if (alias == null)
        {
          foreach (Persona p in this._persona_list)
            {
              if (p is Aliasable)
                {
                  unowned Aliasable a = (Aliasable) p;

                  if (a.alias == null || a.alias.strip () == "")
                    continue;

                  if (alias == null || alias_is_display_id == true)
                    {
                      /* We prefer to not have an alias which is the same as the
                       * Persona's display-id, since having such an alias
                       * implies that it's the default. However, we prefer using
                       * such an alias to using the Persona's UID, which is our
                       * ultimate fallback (below). */
                      alias = a.alias;

                      if (a.alias == p.display_id)
                        alias_is_display_id = true;
                      else if (alias != null)
                        break;
                    }
                }
            }
        }

      debug ("    got alias '%s' from non-writeable personas", alias);

      if (alias == null)
        {
          /* We have to pick a display ID, since none of the personas have an
           * alias available. Pick the display ID from the first persona in the
           * list. */
          alias = this._persona_list.data.display_id;
          debug ("No aliases available for individual; using display ID " +
              "instead: %s", alias);
        }

      /* Only notify if the value has changed. We have to set the private member
       * and notify manually, or we'd end up propagating the new alias back
       * down to all our Personas, even if it's a fallback display ID or
       * something else undesirable. */
      if (this._alias != alias)
        {
          debug ("Changing alias of individual '%s' from '%s' to '%s'.",
              this.id, this._alias, alias);
          this._alias = alias;
          this.notify_property ("alias");
        }
    }

  private void _update_avatar ()
    {
      File avatar = null;

      this._persona_list.foreach ((p) =>
        {
          if (avatar == null && p is HasAvatar)
            {
              avatar = ((HasAvatar) p).avatar;
              return;
            }
        });

      /* only notify if the value has changed */
      if (this.avatar != avatar)
        this.avatar = avatar;
    }

  private void _update_trust_level ()
    {
      TrustLevel trust_level = TrustLevel.PERSONAS;

      foreach (Persona p in this._persona_list)
        {
          if (p.is_user == false &&
              p.store.trust_level == PersonaStoreTrust.NONE)
            trust_level = TrustLevel.NONE;
        }

      /* Only notify if the value has changed */
      if (this.trust_level != trust_level)
        this.trust_level = trust_level;
    }

  private void _update_im_addresses ()
    {
      /* populate the IM addresses as the union of our Personas' addresses */
      foreach (var persona in this.personas)
        {
          if (persona is IMable)
            {
              var imable = (IMable) persona;
              imable.im_addresses.foreach ((k, v) =>
                {
                  var cur_protocol = (string) k;
                  var cur_addresses = (GenericArray<string>) v;
                  var old_im_array = this._im_addresses.lookup (cur_protocol);
                  var im_array = new GenericArray<string> ();

                  /* use a set to eliminate duplicates */
                  var address_set = new HashSet<string> (str_hash, str_equal);
                  if (old_im_array != null)
                    {
                      old_im_array.foreach ((old_address) =>
                        {
                          address_set.add ((string) old_address);
                        });
                    }
                  cur_addresses.foreach ((cur_address) =>
                    {
                      address_set.add ((string) cur_address);
                    });
                  foreach (string addr in address_set)
                    im_array.add (addr);

                  this._im_addresses.insert (cur_protocol, im_array);
                });
            }
        }
      this.notify_property ("im-addresses");
    }

  private void _connect_to_persona (Persona persona)
    {
      persona.notify["alias"].connect (this._notify_alias_cb);
      persona.notify["avatar"].connect (this._notify_avatar_cb);
      persona.notify["presence-message"].connect (this._notify_presence_cb);
      persona.notify["presence-type"].connect (this._notify_presence_cb);
      persona.notify["im-addresses"].connect (this._notify_im_addresses_cb);
      persona.notify["is-favourite"].connect (this._notify_is_favourite_cb);

      if (persona is Groupable)
        {
          ((Groupable) persona).group_changed.connect (
              this._persona_group_changed_cb);
        }
    }

  private void _disconnect_from_persona (Persona persona)
    {
      persona.notify["alias"].disconnect (this._notify_alias_cb);
      persona.notify["avatar"].disconnect (this._notify_avatar_cb);
      persona.notify["presence-message"].disconnect (
          this._notify_presence_cb);
      persona.notify["presence-type"].disconnect (this._notify_presence_cb);
      persona.notify["im-addresses"].disconnect (
          this._notify_im_addresses_cb);
      persona.notify["is-favourite"].disconnect (
          this._notify_is_favourite_cb);

      if (persona is Groupable)
        {
          ((Groupable) persona).group_changed.disconnect (
              this._persona_group_changed_cb);
        }
    }

  private void _set_personas (GLib.List<Persona>? persona_list,
      Individual? replacement_individual)
    {
      HashSet<Persona> persona_set = new HashSet<Persona> (null, null);
      GLib.List<Persona> added = null;
      GLib.List<Persona> removed = null;

      /* Determine which Personas have been added */
      foreach (Persona p in persona_list)
        {
          if (!this._persona_set.contains (p))
            {
              /* Keep track of how many Personas are users */
              if (p.is_user)
                this._persona_user_count++;

              added.prepend (p);

              this._persona_set.add (p);
              this._connect_to_persona (p);

              /* Increment the Persona count for this PersonaStore */
              unowned PersonaStore store = p.store;
              uint num_from_store = this._stores.get (store);
              if (num_from_store == 0)
                {
                  this._stores.set (store, num_from_store + 1);
                }
              else
                {
                  this._stores.set (store, 1);

                  store.removed.connect (this._store_removed_cb);
                  store.personas_changed.connect (
                      this._store_personas_changed_cb);
                }
            }

          persona_set.add (p);
        }

      /* Determine which Personas have been removed */
      foreach (Persona p in this._persona_list)
        {
          if (!persona_set.contains (p))
            {
              /* Keep track of how many Personas are users */
              if (p.is_user)
                this._persona_user_count--;

              removed.prepend (p);

              /* Decrement the Persona count for this PersonaStore */
              unowned PersonaStore store = p.store;
              uint num_from_store = this._stores.get (store);
              if (num_from_store > 1)
                {
                  this._stores.set (store, num_from_store - 1);
                }
              else
                {
                  store.removed.disconnect (this._store_removed_cb);
                  store.personas_changed.disconnect (
                      this._store_personas_changed_cb);

                  this._stores.unset (store);
                }

              this._disconnect_from_persona (p);
              this._persona_set.remove (p);
            }
        }

      /* Update the Persona list. We just copy the list given to us to save
       * repeated insertions/removals and also to ensure we retain the ordering
       * of the Personas we were given. */
      this._persona_list = persona_list.copy ();

      this.personas_changed (added, removed);

      /* Update this.is_user */
      bool new_is_user = (this._persona_user_count > 0) ? true : false;
      if (new_is_user != this.is_user)
        this.is_user = new_is_user;

      /* If all the Personas have been removed, remove the Individual */
      if (this._persona_set.size < 1)
        {
          this.removed (replacement_individual);
          return;
        }

      /* TODO: Base this upon our ID in permanent storage, once we have that. */
      if (this.id == null && this._persona_list.data != null)
        this.id = this._persona_list.data.uid;

      /* Update our aggregated fields and notify the changes */
      this._update_fields ();
    }

  internal void replace (Individual replacement_individual)
    {
      this._set_personas (null, replacement_individual);
    }
}

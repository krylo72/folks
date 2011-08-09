/*
 * Copyright (C) 2011 Collabora Ltd.
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
 *         Travis Reitter <travis.reitter@collabora.co.uk>
 *         Marco Barisione <marco.barisione@collabora.co.uk>
 *         Raul Gutierrez Segales <raul.gutierrez.segales@collabora.co.uk>
 */

using Gee;
using GLib;
using Folks;
using Tracker;
using Tracker.Sparql;

/**
 * A persona subclass which represents a single nco:Contact.
 */
public class Trf.Persona : Folks.Persona,
    AvatarDetails,
    BirthdayDetails,
    EmailDetails,
    FavouriteDetails,
    GenderDetails,
    ImDetails,
    LocalIdDetails,
    NameDetails,
    NoteDetails,
    PhoneDetails,
    PostalAddressDetails,
    RoleDetails,
    UrlDetails,
    WebServiceDetails
{
  private string _nickname;
  private bool _is_favourite;
  private const string[] _linkable_properties =
      {"im-addresses", "local-ids", "web-service-addresses"};
  private HashSet<FieldDetails> _phone_numbers;
  private Set<FieldDetails> _phone_numbers_ro;
  private HashSet<FieldDetails> _email_addresses;
  private Set<FieldDetails> _email_addresses_ro;
  private weak Sparql.Cursor _cursor;
  private string _tracker_id;
  private const string[] _writeable_properties =
    {
      "alias",
      "phone-numbers",
      "email-addresses",
      "avatar",
      "structured-name",
      "full-name",
      "gender",
      "birthday",
      "roles",
      "notes",
      "urls",
      "im-addresses",
      "is-favourite",
      "local-ids",
      "web-service-addresses"
    };

  /**
   * A nickname for the Persona.
   *
   * See {@link Folks.NameDetails.nickname}.
   */
  public string nickname
    {
      get { return this._nickname; }

      set
        {
          if (this._nickname == value)
            return;
          this._nickname = value;
          this.notify_property ("nickname");
          ((Trf.PersonaStore) this.store)._set_nickname (this, value);
        }
    }

  /**
   * {@inheritDoc}
   */
  public Set<FieldDetails> phone_numbers
    {
      get { return this._phone_numbers_ro; }
      public set
        {
          ((Trf.PersonaStore) this.store)._set_phones (this, value);
        }
    }

  /**
   * {@inheritDoc}
   */
  public Set<FieldDetails> email_addresses
    {
      get { return this._email_addresses_ro; }
      public set
        {
          ((Trf.PersonaStore) this.store)._set_emails (this, value);
        }
    }

  /**
   * {@inheritDoc}
   */
  public override string[] linkable_properties
    {
      get { return this._linkable_properties; }
    }

  /**
   * {@inheritDoc}
   *
   * @since UNRELEASED
   */
  public override string[] writeable_properties
    {
      get { return this._writeable_properties; }
    }

  private LoadableIcon? _avatar = null;
  /**
   * An avatar for the Persona.
   *
   * See {@link Folks.AvatarDetails.avatar}.
   *
   * @since UNRELEASED
   */
  public LoadableIcon? avatar
    {
      get { return this._avatar; }
      public set
        {
          ((Trf.PersonaStore) this.store)._set_avatar (this, value);
        }
    }

  private StructuredName _structured_name;
  /**
   * {@inheritDoc}
   */
  public StructuredName structured_name
    {
      get { return this._structured_name; }
      public set
        {
          ((Trf.PersonaStore) this.store)._set_structured_name (this, value);
        }
    }

  private string _full_name;
  /**
   * {@inheritDoc}
   */
  public string full_name
    {
      get { return this._full_name; }
      public set
        {
          ((Trf.PersonaStore) this.store)._set_full_name (this, value);
        }
    }

  private Gender _gender;
  /**
   * {@inheritDoc}
   */
  public Gender gender
    {
      get { return this._gender; }
      public set
        {
          ((Trf.PersonaStore) this.store)._set_gender (this, value);
        }
    }

  private DateTime _birthday;
  /**
   * {@inheritDoc}
   */
  public DateTime birthday
    {
      get { return this._birthday; }
      public set
        {
          ((Trf.PersonaStore) this.store)._set_birthday (this, value);
        }
    }

  /**
   * {@inheritDoc}
   */
  public string? calendar_event_id
    {
      /* Unsupported */
      get { return null; }
      private set {}
    }

  private HashSet<Role> _roles;
  private Set<Role> _roles_ro;

  /**
   * {@inheritDoc}
   */
  public Set<Role> roles
    {
      get { return this._roles_ro; }
      public set
        {
          ((Trf.PersonaStore) this.store)._set_roles (this, value);
        }
    }

  private HashSet<Note> _notes;
  private Set<Note> _notes_ro;

  /**
   * {@inheritDoc}
   */
  public Set<Note> notes
    {
      get { return this._notes_ro; }
      set
        {
          ((Trf.PersonaStore) this.store)._set_notes (this, value);
        }
    }

  private HashSet<FieldDetails> _urls;
  private Set<FieldDetails> _urls_ro;

  /**
   * {@inheritDoc}
   */
  public Set<FieldDetails> urls
    {
      get { return this._urls_ro; }
      public set
        {
          ((Trf.PersonaStore) this.store)._set_urls (this, value);
        }
    }

  private HashSet<PostalAddress> _postal_addresses;
  private Set<PostalAddress> _postal_addresses_ro;

  /**
   * {@inheritDoc}
   */
  public Set<PostalAddress> postal_addresses
    {
      get { return this._postal_addresses_ro; }
      public set
        {
          ((Trf.PersonaStore) this.store)._set_postal_addresses (this, value);
        }
    }

  private HashTable<string, HashTable<string, string>> _tracker_ids_ims =
  new HashTable<string, HashTable<string, string>> (str_hash, str_equal);

  private HashMultiMap<string, string> _im_addresses =
      new HashMultiMap<string, string> ();

  /**
   * {@inheritDoc}
   */
  public MultiMap<string, string> im_addresses
    {
      get { return this._im_addresses; }
      public set
        {
          ((Trf.PersonaStore) this.store)._set_im_addresses (this,
              value);
        }
    }

  /**
   * Whether this contact is a user-defined favourite.
   */
  public bool is_favourite
      {
        get { return this._is_favourite; }

        set
          {
            if (this._is_favourite == value)
              return;

            /* Note:
             * this property will be set (and notified)
             * once we receive a notification event from Tracker
             */
            ((Trf.PersonaStore) this.store)._set_is_favourite (this, value);
          }
      }

  private HashSet<string> _local_ids;
  private Set<string> _local_ids_ro;

  /**
   * IDs used to link {@link Trf.Persona}s.
   */
  public Set<string> local_ids
    {
      get
        {
          if (this._local_ids.contains (this.uid) == false)
            {
              this._local_ids.add (this.uid);
            }
          return this._local_ids_ro;
        }
      set
        {
          if (value.contains (this.uid) == false)
            {
              value.add (this.uid);
            }
          ((Trf.PersonaStore) this.store)._set_local_ids (this, value);
        }
    }

  private HashMultiMap<string, string> _web_service_addresses =
      new HashMultiMap<string, string> ();

  /**
   * {@inheritDoc}
   */
  public MultiMap<string, string> web_service_addresses
    {
      get { return this._web_service_addresses; }
      set
        {
          ((Trf.PersonaStore) this.store)._set_web_service_addrs (this, value);
        }
    }

  /**
   * Build a IID.
   *
   * @param store_id the {@link PersonaStore.id}
   * @param tracker_id the tracker id belonging to nco:PersonContact
   * @return a valid IID
   *
   * @since 0.5.0
   */
  internal static string build_iid (string store_id, string tracker_id)
    {
      return "%s:%s".printf (store_id, tracker_id);
    }

  /**
   * Create a new persona.
   *
   * Create a new persona for the {@link PersonaStore} `store`, representing
   * the nco:Contact whose details are stored in the cursor.
   */
  public Persona (PersonaStore store, string tracker_id,
                  Sparql.Cursor? cursor = null)
    {
      string uid = this.build_uid (BACKEND_NAME, store.id, tracker_id);
      string iid = this.build_iid (store.id, tracker_id);
      bool is_user = false;
      string fullname = "";

      if (cursor != null)
        {
          fullname = cursor.get_string (Trf.Fields.FULL_NAME).dup ();
          var contact_urn = cursor.get_string (Trf.Fields.CONTACT_URN);
          if (contact_urn == Trf.OntologyDefs.DEFAULT_CONTACT_URN)
            {
              is_user = true;
            }
        }

      debug ("Creating new Trf.Persona with iid '%s'", iid);

      Object (display_id: fullname,
              uid: uid,
              iid: iid,
              store: store,
              is_user: is_user);

      this._gender = Gender.UNSPECIFIED;
      this._full_name = fullname;
      this._tracker_id = tracker_id;
      this._structured_name = new StructuredName (null, null, null, null, null);
      this._phone_numbers = new HashSet<FieldDetails> ();
      this._phone_numbers_ro = this._phone_numbers.read_only_view;
      this._email_addresses = new HashSet<FieldDetails> ();
      this._email_addresses_ro = this._email_addresses.read_only_view;
      this._roles = new HashSet<Role> ((GLib.HashFunc) Role.hash,
          (GLib.EqualFunc) Role.equal);
      this._roles_ro = this._roles.read_only_view;
      this._notes = new HashSet<Note> ((GLib.HashFunc) Note.hash,
          (GLib.EqualFunc) Note.equal);
      this._notes_ro = this._notes.read_only_view;
      this._urls = new HashSet<FieldDetails> ();
      this._urls_ro = this._urls.read_only_view;
      this._postal_addresses = new HashSet<PostalAddress> ();
      this._postal_addresses_ro = this._postal_addresses.read_only_view;
      this._local_ids = new HashSet<string> ();
      this._local_ids_ro = this._local_ids.read_only_view;

      if (cursor != null)
        {
          this._cursor = cursor;
          this._update ();
        }
    }

  internal string tracker_id ()
    {
      return this._tracker_id;
    }

  /**
   * {@inheritDoc}
   */
  public override void linkable_property_to_links (string prop_name,
      Folks.Persona.LinkablePropertyCallback callback)
    {
      if (prop_name == "im-addresses")
        {
          foreach (var protocol in this._im_addresses.get_keys ())
            {
              var im_addresses = this._im_addresses.get (protocol);

              foreach (string address in im_addresses)
                  callback (protocol + ":" + address);
            }
        }
      else if (prop_name == "local-ids")
        {
          foreach (var id in this._local_ids)
            {
              callback (id);
            }
        }
      else if (prop_name == "web-service-addresses")
        {
          foreach (var web_service in this._web_service_addresses.get_keys ())
            {
              var web_service_addresses =
                  this._web_service_addresses.get (web_service);

              foreach (string address in web_service_addresses)
                  callback (web_service + ":" + address);
            }
        }
      else
        {
          /* Chain up */
          base.linkable_property_to_links (prop_name, callback);
        }
    }

  ~Persona ()
    {
      debug ("Destroying Trf.Persona '%s': %p", this.uid, this);
    }

  internal void _update_full_name (string? fn)
    {
      if (fn != null && this.full_name != fn)
        {
          this._full_name = fn;
          this.notify_property ("full-name");
        }
    }

  internal void _update_nickname (string? nickname)
    {
      if (nickname != null && this._nickname != nickname)
        {
          this._nickname = nickname;
          this.notify_property ("nickname");
        }
    }

  internal void _update_family_name (string? family_name)
    {
      if (family_name != null)
        {
          this._structured_name.family_name = family_name;
          this.notify_property ("structured-name");
        }
    }

  internal void _update_given_name (string? given_name)
    {
      if (given_name != null)
        {
          this._structured_name.given_name = given_name;
          this.notify_property ("structured-name");
        }
    }

  internal void _update_additional_names (string? additional_names)
    {
      if (additional_names != null)
        {
          this._structured_name.additional_names = additional_names;
          this.notify_property ("structured-name");
        }
    }

  internal void _update_prefixes (string? prefixes)
    {
      if (prefixes != null)
        {
          this._structured_name.prefixes = prefixes;
          this.notify_property ("structured-name");
        }
    }

  internal void _update_suffixes (string? suffixes)
    {
      if (suffixes != null)
        {
          this._structured_name.suffixes = suffixes;
          this.notify_property ("structured-name");
        }
    }

  internal void _update ()
    {
      this._update_names ();
      this._update_avatar ();
      this._update_im_addresses ();
      this._update_phones ();
      this._update_email_addresses ();
      this._update_urls ();
      this._update_favourite ();
      this._update_roles ();
      this._update_bday ();
      this._update_note ();
      this._update_gender ();
      this._update_postal_addresses ();
      this._update_local_ids ();
    }

  private void _update_postal_addresses ()
    {
      string postal_field = this._cursor.get_string
          (Trf.Fields.POSTAL_ADDRESS).dup ();

      if (postal_field == null)
        {
          return;
        }

      var postal_addresses = new HashSet<PostalAddress> ();

      string[] addresses_a = postal_field.split ("\n");

      foreach (var a in addresses_a)
        {
          bool address_empty = true;
          string[] a_info = a.split ("\t");
          for (int i = 0; i < a_info.length; i++)
            {
              if (a_info[i] != null && a_info[i] != "")
                {
                  address_empty = false;
                  break;
                }
            }

          if (address_empty)
            continue;

          var types = new HashSet<string> ();

          var pa = new PostalAddress (a_info[Trf.PostalAddressFields.POBOX],
              a_info[Trf.PostalAddressFields.EXTENDED_ADDRESS],
              a_info[Trf.PostalAddressFields.STREET_ADDRESS],
              a_info[Trf.PostalAddressFields.LOCALITY],
              a_info[Trf.PostalAddressFields.REGION],
              a_info[Trf.PostalAddressFields.POSTALCODE],
              a_info[Trf.PostalAddressFields.COUNTRY],
              null, types,
              a_info[Trf.PostalAddressFields.TRACKER_ID]);

          postal_addresses.add (pa);
        }

      this._postal_addresses = postal_addresses;
      this._postal_addresses_ro = this._postal_addresses.read_only_view;
    }

 private void _update_local_ids ()
    {
      string local_ids = this._cursor.get_string
          (Trf.Fields.LOCAL_IDS_PROPERTY).dup ();

     if (local_ids == null)
        {
          return;
        }

      this._set_local_ids (local_ids);
    }

  internal bool _add_postal_address (PostalAddress postal_address)
    {
      foreach (var pa in this._postal_addresses)
        {
          if (postal_address.equal (pa))
            {
              return false;
            }
        }

      this._postal_addresses.add (postal_address);
      this.notify_property ("postal-addresses");
      return true;
    }

  internal bool _remove_postal_address (string tracker_id)
    {
      foreach (var pa in this._postal_addresses)
        {
          if (pa.uid == tracker_id)
            {
              this._postal_addresses.remove (pa);
              this.notify_property ("postal-addresses");
              return true;
            }
        }
      return false;
    }

  private void _update_gender ()
    {
      string gender = this._cursor.get_string (Trf.Fields.GENDER).dup ();
      int gender_id = 0;

      if (gender != null)
        {
          gender_id = int.parse (gender);
        }

      this._set_gender (gender_id);
    }

  internal void _set_gender (int gender_id)
    {
      if (gender_id == 0)
        {
          this._gender = Gender.UNSPECIFIED;
        }
      else
        {
          var trf_store = (Trf.PersonaStore) this.store;

          if (gender_id == trf_store.get_gender_male_id ())
            {
              this._gender = Gender.MALE;
            }
          else if (gender_id == trf_store.get_gender_female_id ())
            {
              this._gender = Gender.FEMALE;
            }
        }

      this.notify_property ("gender");
    }

  private void _update_note ()
    {
      string note = this._cursor.get_string (Trf.Fields.NOTE).dup ();
      this._set_note (note);
    }

  internal void _set_note (string? note_content)
    {
      if (note_content != null)
        {
          var note = new Note (note_content);
          this._notes.add ((owned) note);
        }
      else
        {
          this._notes.clear ();
        }
      this.notify_property ("notes");
    }

  private void _update_bday ()
    {
      string bday = this._cursor.get_string (Trf.Fields.BIRTHDAY).dup ();
      this._set_birthday (bday);
    }

  internal void _set_birthday (string? birthday)
    {
      if (birthday != null && birthday != "")
        {
          TimeVal t = TimeVal ();
          t.from_iso8601 (birthday);
          this._birthday = new DateTime.from_timeval_utc (t);
          this.notify_property ("birthday");
        }
      else
        {
          if (this._birthday != null)
            {
              this._birthday = null;
              this.notify_property ("birthday");
            }
        }
    }

  private void _update_roles ()
    {
      string roles_field = this._cursor.get_string (
          Trf.Fields.ROLES).dup ();

      if (roles_field == null)
        {
          return;
        }

      HashSet<Role> roles = new HashSet<Role> (
          (GLib.HashFunc) Role.hash,
          (GLib.EqualFunc) Role.equal);

      string[] roles_a = roles_field.split ("\n");

      foreach (var r in roles_a)
        {
          string[] r_info = r.split ("\t");
          var tracker_id = r_info[Trf.RoleFields.TRACKER_ID];
          var role = r_info[Trf.RoleFields.ROLE];
          var title = r_info[Trf.RoleFields.TITLE];
          var organisation = r_info[Trf.RoleFields.DEPARTMENT];

          var new_role = new Role (title, organisation, tracker_id);
          new_role.role = role;
          roles.add (new_role);
        }

      this._roles = roles;
      this._roles_ro = this._roles.read_only_view;
    }

  internal bool _add_role (string tracker_id, string? role, string? title, string? org)
    {
      var new_role = new Role (title, org, tracker_id);
      new_role.role = role;

      if (this._roles.add (new_role))
        {
          this.notify_property ("roles");
          return true;
        }
      return false;
    }

  internal bool _remove_role (string tracker_id)
    {
      foreach (var r in this._roles)
        {
          if (r.uid == tracker_id)
            {
              this._roles.remove (r);
              this.notify_property ("roles");
              return true;
            }
        }

      return false;
    }

  private void _update_names ()
    {
      string fullname = this._cursor.get_string (Trf.Fields.FULL_NAME).dup ();
      this._update_full_name (fullname);

      string nickname = this._cursor.get_string (Trf.Fields.NICKNAME).dup ();
      this._update_nickname (nickname);

      string family_name = this._cursor.get_string (
          Trf.Fields.FAMILY_NAME).dup ();
      this._update_family_name (family_name);

      string given_name  = this._cursor.get_string (
          Trf.Fields.GIVEN_NAME).dup ();
      this._update_given_name (given_name);

      string additional_names = this._cursor.get_string (
          Trf.Fields.ADDITIONAL_NAMES).dup ();
      this._update_additional_names (additional_names);

      string prefixes = this._cursor.get_string (Trf.Fields.PREFIXES).dup ();
      this._update_prefixes (prefixes);

      string suffixes = this._cursor.get_string (Trf.Fields.SUFFIXES).dup ();
      this._update_suffixes (suffixes);
    }

  private void _update_avatar ()
    {
      string avatar_url = this._cursor.get_string (
          Trf.Fields.AVATAR_URL).dup ();
      this._set_avatar_from_uri (avatar_url);
    }

  internal bool _set_avatar_from_uri (string? avatar_url)
    {
      LoadableIcon _avatar = null;
      if (avatar_url != null && avatar_url != "")
        {
          _avatar = new FileIcon (File.new_for_uri (avatar_url));
        }

      this._set_avatar (_avatar);

      return true;
    }

  internal bool _set_avatar (LoadableIcon? avatar)
    {
      this._avatar = avatar;
      this.notify_property ("avatar");
      return true;
    }

  internal bool _set_local_ids (string local_ids)
    {
      this._local_ids =
          (HashSet<string>) Trf.PersonaStore.unserialize_local_ids (local_ids);
      this._local_ids_ro = this._local_ids.read_only_view;
      this.notify_property ("local-ids");
      return true;
    }

  internal bool _set_web_service_addrs (string ws_addrs)
    {
      this._web_service_addresses =
        (HashMultiMap<string, string>)
            Trf.PersonaStore.unserialize_web_services (ws_addrs);
      this.notify_property ("web-service-addresses");
      return true;
    }

  private void _update_im_addresses ()
    {
      string addresses = this._cursor.get_string (
          Trf.Fields.IM_ADDRESSES).dup ();

      if (addresses == null)
        {
          return;
        }

      this._im_addresses.clear ();

      string[] addresses_a = addresses.split ("\n");

      foreach (var addr in addresses_a)
        {
          string[] addr_info = addr.split ("\t");
          var tracker_id = addr_info[Trf.IMFields.TRACKER_ID];
          var proto = addr_info[Trf.IMFields.PROTO];
          var account_id = addr_info[Trf.IMFields.ID];
          var nickname = addr_info[Trf.IMFields.IM_NICKNAME];

          this._update_nickname (nickname);
          this._add_im_address (tracker_id, proto, account_id, false);
        }

      this.notify_property ("im-addresses");
    }

  internal bool _add_im_address (string tracker_id, string im_proto,
      string account_id, bool notify = true)
    {
      try
        {
          var account_id_copy = account_id.dup ();
          var normalised_addr = (owned) normalise_im_address
              ((owned) account_id_copy, im_proto);

          this._im_addresses.set (im_proto, normalised_addr);

          var im_proto_hash = new HashTable<string, string> (str_hash,
              str_equal);
          var proto_copy_2 = im_proto.dup ();
          var account_id_copy_2 = account_id.dup ();
          im_proto_hash.insert ((owned) proto_copy_2,
              (owned) account_id_copy_2);
          var tracker_id_copy = tracker_id.dup ();
          this._tracker_ids_ims.insert ((owned) tracker_id_copy,
                  (owned) im_proto_hash);

          if (notify)
            {
              this.notify_property ("im-addresses");
            }
        }
      catch (Folks.ImDetailsError e)
        {
          GLib.warning (
              "Problem when trying to normalise address: %s\n",
              e.message);
        }

      return true;
    }

  internal bool _remove_im_address (string tracker_id, bool notify = true)
    {
      var proto_im = this._tracker_ids_ims.lookup (tracker_id);

      if (proto_im == null)
        return false;

      var proto = proto_im.get_keys ().nth_data (0);
      var im_addr = proto_im.lookup (proto);

      if (this._im_addresses.remove (proto, im_addr))
        {
          this._tracker_ids_ims.remove (tracker_id);
          if (notify)
            {
              this.notify_property ("im-addresses");
            }

          return true;
        }

      return false;
    }

  private void _update_phones ()
    {
      string phones_field = this._cursor.get_string (Trf.Fields.PHONES).dup ();

      if (phones_field == null)
        {
          return;
        }

      var phones = new HashSet<FieldDetails> ();
      string[] phones_a = phones_field.split ("\n");

      foreach (var p in phones_a)
        {
          if (p != null && p != "")
            {
              string[] p_info = p.split ("\t");
              var fd = new FieldDetails (p_info[Trf.PhoneFields.PHONE]);
              fd.set_parameter ("tracker_id",
                  p_info[Trf.PhoneFields.TRACKER_ID]);
              phones.add (fd);
            }
        }

      this._phone_numbers = phones;
      this._phone_numbers_ro = this._phone_numbers.read_only_view;
    }

  internal bool _add_phone (string phone, string tracker_id)
    {
      bool found = false;

      foreach (var p in this._phone_numbers)
        {
          if (p.get_parameter_values ("tracker_id").contains (tracker_id))
            {
              found = true;
              break;
            }
        }

      if (!found)
        {
          var fd = new FieldDetails (phone);
          fd.set_parameter ("tracker_id", tracker_id);
          this._phone_numbers.add (fd);
          this.notify_property ("phone-numbers");
        }

      return !found;
    }

  internal bool _remove_phone (string tracker_id)
    {
      bool found = false;

      foreach (var p in this._phone_numbers)
        {
          if (p.get_parameter_values ("tracker_id").contains (tracker_id))
            {
              this._phone_numbers.remove (p);
              found = true;
              break;
            }
        }

      if (found)
       {
         this.notify_property ("phone-numbers");
       }

      return found;
    }

  internal bool _add_email (string addr, string tracker_id)
    {
      bool found = false;

      foreach (var e in this._email_addresses)
        {
          if (e.get_parameter_values ("tracker_id").contains (tracker_id))
            {
              found = true;
              break;
            }
        }

      if (!found)
        {
          var fd = new FieldDetails (addr);
          fd.set_parameter ("tracker_id", tracker_id);
          this._email_addresses.add (fd);
          this.notify_property ("email-addresses");
        }

      return !found;
    }

  internal bool _remove_email (string tracker_id)
    {
      bool found = false;

      foreach (var e in this._email_addresses)
        {
          if (e.get_parameter_values ("tracker_id").contains (tracker_id))
            {
              this._email_addresses.remove (e);
              found = true;
              break;
            }
        }

      if (found)
       {
         this.notify_property ("email-addresses");
       }

      return found;
    }

  private void _update_email_addresses ()
    {
      string emails_field = this._cursor.get_string (Trf.Fields.EMAILS).dup ();

      if (emails_field == null)
        {
          return;
        }

      var email_addresses = new HashSet<FieldDetails> ();
      string[] emails_a = emails_field.split (",");

      foreach (var e in emails_a)
        {
          if (e != null && e != "")
            {
              string[] id_addr = e.split ("\t");
              var fd = new FieldDetails (id_addr[Trf.EmailFields.EMAIL]);
              fd.set_parameter ("tracker_id",
                  id_addr[Trf.EmailFields.TRACKER_ID]);
              email_addresses.add (fd);
            }
        }

      this._email_addresses = email_addresses;
      this._email_addresses_ro = this._email_addresses.read_only_view;
    }

  private void _update_urls ()
    {
      var urls = new HashSet<FieldDetails> ();
      var _urls_field = this._cursor.get_string (Trf.Fields.URLS).dup ();

      if (_urls_field == null)
        return;

      string[] urls_table = _urls_field.split ("\n");

      foreach (var row in urls_table)
        {
          string[] u = row.split ("\t");
          var tracker_id = u[Trf.UrlsFields.TRACKER_ID];

          for (int i=1; i< u.length; i++)
            {
              if (u[i] == null || u[i] == "")
                continue;

              string type = "";
              switch (i)
                {
                  case Trf.UrlsFields.BLOG:
                    type = "blog";
                    break;
                  case Trf.UrlsFields.WEBSITE:
                    type = "website";
                    break;
                  case Trf.UrlsFields.URL:
                    type = "url";
                    break;
                }

              var fd = new FieldDetails (u[i]);
              fd.set_parameter ("tracker_id", tracker_id);
              fd.set_parameter ("type", type);
              urls.add (fd);
            }
        }

      this._urls = urls;
      this._urls_ro = this._urls.read_only_view;
    }

  internal bool _add_url (string url, string tracker_id, string type = "")
    {
      bool found = false;

      foreach (var p in this._urls)
        {
          if (p.get_parameter_values ("tracker_id").contains (tracker_id))
            {
              found = true;
              break;
            }
        }

      if (!found)
        {
          var fd = new FieldDetails (url);
          fd.set_parameter ("tracker_id", tracker_id);
          fd.set_parameter ("type", type);
          this._urls.add (fd);
          this.notify_property ("urls");
        }

      return !found;
    }

  internal bool _remove_url (string tracker_id)
    {
      bool found = false;

      foreach (var u in this._urls)
        {
          if (u.get_parameter_values ("tracker_id").contains (tracker_id))
            {
              this._urls.remove (u);
              found = true;
            }
        }

      if (found)
        this.notify_property ("urls");

      return found;
    }

  private void _update_favourite ()
    {
      var favourite = this._cursor.get_string (Trf.Fields.FAVOURITE).dup ();

      this._is_favourite = false;

      if (favourite != null)
        {
          var trf_store = (Trf.PersonaStore) this.store;
          int favorite_tracker_id = trf_store.get_favorite_id ();
          foreach (var tag in favourite.split (","))
            {
              if (int.parse (tag) == favorite_tracker_id)
                {
                  this._is_favourite = true;
                }
            }
        }
    }

  /**
   * This method sets the is_favourite attribute internally.
   * That is, it should be used as a result of an event fired by
   * Tracker since this method doesn't propagate changes back
   * to Tracker again.
   */
  internal void _set_favourite (bool is_fav)
    {
      this._is_favourite = is_fav;
      this.notify_property ("is-favourite");
    }
}

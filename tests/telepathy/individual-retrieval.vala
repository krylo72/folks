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
 * Authors: Travis Reitter <travis.reitter@collabora.co.uk>
 */

using DBus;
using TelepathyGLib;
using TpTests;
using Tpf;
using Folks;
using Gee;

public class IndividualRetrievalTests : Folks.TestCase
{
  private TpTests.Backend tp_backend;
  private void* _account_handle;
  private HashSet<string> default_individuals;
  private int _test_timeout = 3;

  public IndividualRetrievalTests ()
    {
      base ("IndividualRetrieval");

      this.tp_backend = new TpTests.Backend ();

      /* IDs of the individuals we expect to see.
       * These are externally opaque, but internally are SHA-1 hashes of the
       * concatenated UIDs of the Personas in the Individual. In these cases,
       * each default_individual contains one Persona.
       * e.g.
       *  telepathy:/org/freedesktop/Telepathy/Account/cm/protocol/account:me@example.com
       * only in each Individual. */
      this.default_individuals = new HashSet<string> (str_hash, str_equal);

      /* me@example.com */
      default_individuals.add ("48fa372a81026063187255e3f5c184665d2ed7ce");
      /* travis@example.com */
      default_individuals.add ("60c91326018f6a60604f8d260fc24a60a5b8512c");
      /* guillaume@example.com */
      default_individuals.add ("6380b17dc511b21a1defd4811f1add97b278f92c");
      /* olivier@example.com */
      default_individuals.add ("0e46c5e74f61908f49550d241f2a1651892a1695");
      /* sjoerd@example.com */
      default_individuals.add ("6b08188cb2ef8cbaca140b277780069b5af8add6");
      /* geraldine@example.com */
      default_individuals.add ("f948d4d2af79085ab860f0ef67bf0c201c4602d4");
      /* helen@example.com */
      default_individuals.add ("f34529a442577b840a75271b464e90666c38c464");
      /* wim@example.com */
      default_individuals.add ("467d13f955e62bf30ebf9620fa052aaee2160260");
      /* christian@example.com */
      default_individuals.add ("07b913b8977c04d2f2011e26a46ea3e3dcfe3e3d");

      this.add_test ("aggregator", this.test_aggregator);
      this.add_test ("aggregator:add", this.test_aggregator_add);

      if (Environment.get_variable ("FOLKS_TEST_VALGRIND") != null)
          this._test_timeout = 10;
    }

  public override void set_up ()
    {
      this.tp_backend.set_up ();
      this._account_handle = this.tp_backend.add_account ("protocol",
          "me@example.com", "cm", "account");
    }

  public override void tear_down ()
    {
      this.tp_backend.remove_account (this._account_handle);
      this.tp_backend.tear_down ();
    }

  public void test_aggregator ()
    {
      var main_loop = new GLib.MainLoop (null, false);

      /* work on a copy so we can mangle it */
      HashSet<string> expected_individuals = new HashSet<string> ();
      foreach (var id in this.default_individuals)
        expected_individuals.add (id);

      /* Set up the aggregator */
      var aggregator = new IndividualAggregator ();
      aggregator.individuals_changed_detailed.connect ((changes) =>
        {
          var added = changes.get_values ();
          var removed = changes.get_keys ();

          foreach (Individual i in added)
            {
              assert (i != null);
              expected_individuals.remove (i.id);
            }

          assert (removed.size == 1);

          foreach (var i in removed)
            {
              assert (i == null);
            }
        });

      /* Kill the main loop after a few seconds. If there are still individuals
       * in the set of expected individuals, the aggregator has either failed or
       * been too slow (which we can consider to be failure). */
      Timeout.add_seconds (this._test_timeout, () =>
        {
          main_loop.quit ();
          return false;
        });

      Idle.add (() =>
        {
          aggregator.prepare.begin ((s,r) =>
            {
              try
                {
                  aggregator.prepare.end (r);
                }
              catch (GLib.Error e1)
                {
                  GLib.critical ("failed to prepare aggregator: %s",
                    e1.message);
                  assert_not_reached ();
                }
            });

          return false;
        });

      main_loop.run ();

      /* We should have enumerated exactly the individuals in the set */
      assert (expected_individuals.size == 0);

      /* necessary to reset the aggregator for the next test */
      aggregator = null;
    }

  public void test_aggregator_add ()
    {
      var main_loop = new GLib.MainLoop (null, false);

      HashSet<string> added_individuals = new HashSet<string> ();
      added_individuals.add ("master.shake@example.com");
      added_individuals.add ("2wycked@example.com");
      added_individuals.add ("carl-brutananadilewski@example.com");

      /* Set up the aggregator */
      var aggregator = new IndividualAggregator ();

      aggregator.individuals_changed_detailed.connect ((changes) =>
        {
          var added = changes.get_values ();
          var removed = changes.get_keys ();

          /* implicitly ignore the default Individuals, since that's covered in
           * other test(s) */
          foreach (Individual i in added)
            {
              assert (i != null);

              /* If the Individual contains a Persona with an ID we provided,
               * mark it as recieved.
               * This intentionally avoids assuming that the Individual's ID is
               * necessarily related to the ID of any of its Persona(s) */
              foreach (Folks.Persona p in i.personas)
                {
                  if (p is Tpf.Persona)
                    if (added_individuals.remove (((Tpf.Persona) p).display_id))
                      break;
                }
            }

          assert (removed.size == 1);

          foreach (var i in removed)
            {
              assert (i == null);
            }
        });

      /* Kill the main loop after a few seconds. If there are still individuals
       * in the set of expected individuals, the aggregator has either failed or
       * been too slow (which we can consider to be failure). */
      Timeout.add_seconds (this._test_timeout, () =>
        {
          main_loop.quit ();
          return false;
        });

      Idle.add (() =>
        {
          aggregator.prepare.begin ((s,r) =>
            {
              try
                {
                  aggregator.prepare.end (r);
                }
              catch (GLib.Error e1)
                {
                  GLib.critical ("failed to prepare aggregator: %s",
                    e1.message);
                  assert_not_reached ();
                }

              /* at this point, all the backends are prepared */

              /* FIXME: the fact that this is so awkward means this is a point
               * of improvement in the API */

              var adding_done = false;

              /* once we see a valid Tpf.PersonaStore, add our new personas */
              var backend_store = BackendStore.dup ();
              foreach (var backend in backend_store.enabled_backends.values)
                {
                  /* PersonaStores can be added after the backend is prepared */
                  backend.persona_store_added.connect ((store) =>
                    {
                      if (store is Tpf.PersonaStore && !adding_done)
                        {
                          this.add_personas.begin ((Tpf.PersonaStore) store,
                            added_individuals);
                          adding_done = true;
                        }
                    });

                  foreach (var store in backend.persona_stores.values)
                    {
                      if (store is Tpf.PersonaStore && !adding_done)
                        {
                          this.add_personas.begin ((Tpf.PersonaStore) store,
                            added_individuals);
                          adding_done = true;
                        }
                    }
                }
            });

          return false;
        });

      main_loop.run ();

      /* We should have received (and removed) the individuals in the set */
      assert (added_individuals.size == 0);

      /* necessary to reset the aggregator for the next test */
      aggregator = null;
    }

  private async void add_personas (Tpf.PersonaStore store,
      HashSet<string>? ids_add)
    {
      try
        {
          yield store.prepare ();

          /* track which IDs have been successfully added, since
           * add_persona_from_details can temporarily fail with
           * PersonaStoreError.STORE_OFFLINE (in which case, we just need to try
           * again later) */
          var ids_remaining = new HashSet<string> (str_hash, str_equal);
          foreach (var contact_id in ids_add)
            ids_remaining.add (contact_id);

          Idle.add (() =>
            {
              var try_again = false;

              foreach (var id in ids_remaining)
                {
                  var details = new HashTable<string, GLib.Value?> (str_hash,
                      str_equal);
                  details.insert ("contact", id);

                  /* we can end up adding the same ID twice, since this async
                   * function can be called a second time before the first
                   * completes. But add_persona_from_details() is idempotent, so
                   * this is acceptable (and not worth the extra code) */
                  store.add_persona_from_details.begin (details, (s2, res) =>
                      {
                        try
                          {
                            store.add_persona_from_details.end (res);

                            var id_added_value = details.lookup ("contact");
                            var id_added = id_added_value.get_string ();
                            if (id_added != null)
                              ids_remaining.remove (id_added);
                          }
                        catch (GLib.Error e1)
                          {
                            /* STORE_OFFLINE is acceptable -- see above */
                            if (!(e1 is PersonaStoreError.STORE_OFFLINE))
                              {
                                GLib.critical ("failed to add persona: %s",
                                  e1.message);
                                assert_not_reached ();
                              }
                          }
                      });

                  try_again = (ids_remaining.size > 0);
                  if (try_again)
                    break;
                }

              return try_again;
            });
        }
      catch (GLib.Error e2)
        {
          warning ("Error preparing PersonaStore '%s': %s", store.id,
              e2.message);
          assert_not_reached ();
        }
    }
}

public int main (string[] args)
{
  Test.init (ref args);

  TestSuite root = TestSuite.get_root ();
  root.add_suite (new IndividualRetrievalTests ().get_suite ());

  Test.run ();

  return 0;
}

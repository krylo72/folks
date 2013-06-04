/* test-case.vala
 *
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.

 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.

 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
 *
 * Author:
 *      Renato Araujo Oliveira Filho <renato@canonical.com>
 */

using Folks;
using Gee;

/**
 * A test case for the dummy backend, which is configured as the
 * primary store and as the only backend allowed.
 */
public class DummyTest.TestCase : Folks.TestCase
{
  /**
   * The dummy test backend.
   */
  public Dummy.Backend dummy_backend;

  /**
   * The default persona store
   */
  public Dummy.PersonaStore dummy_persona_store;

  public TestCase (string name)
    {
      base (name);

      Environment.set_variable ("FOLKS_BACKENDS_ALLOWED", "dummy", true);
      Environment.set_variable ("FOLKS_PRIMARY_STORE", "dummy-store", true);
    }

  public override void set_up ()
    {
      base.set_up ();

      this.dummy_backend = new Dummy.Backend ();
      this.configure_primary_store ();
    }

  public virtual void configure_primary_store ()
    {
      var persona_stores = new HashSet<PersonaStore>();
      string[] writable_properties = { Folks.PersonaStore.detail_key (PersonaDetail.BIRTHDAY),
          Folks.PersonaStore.detail_key (PersonaDetail.EMAIL_ADDRESSES),
          Folks.PersonaStore.detail_key (PersonaDetail.PHONE_NUMBERS) };

      this.dummy_persona_store = new Dummy.PersonaStore ("dummy-store", "Dummy personas", writable_properties);
      this.dummy_persona_store.persona_type = typeof (Dummy.FatPersona);

      var main_loop = new GLib.MainLoop (null, false);
      this.dummy_backend.persona_store_added.connect ((store) => 
        {
            GLib.debug ("Persona store created\n");
            main_loop.quit();        
            main_loop = null;
        });   

      persona_stores.add (this.dummy_persona_store);
      this.dummy_backend.register_persona_stores (persona_stores);

      GLib.debug ("Wait for mainloop\n");
      if (main_loop != null) 
        {
          TestUtils.loop_run_with_timeout (main_loop, 3);
        }
      GLib.debug ("Wait for mainloop:DONE\n");
    }

  public override void tear_down ()
    {
      if (this.dummy_backend != null)
        {
          this.dummy_backend.unprepare.begin((obj, res) => {
            try { 
              this.dummy_backend.unprepare.end(res);
            } catch (GLib.Error error) {
            } 
          });
          this.dummy_backend = null;
        }

      base.tear_down ();
    }
}
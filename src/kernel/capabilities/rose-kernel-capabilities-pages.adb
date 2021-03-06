with Rose.Kernel.Processes;

package body Rose.Kernel.Capabilities.Pages is

   ------------
   -- Handle --
   ------------

   procedure Handle
     (Cap    : Rose.Capabilities.Layout.Capability_Layout;
      Params : Rose.Invocation.Invocation_Access)
   is
      Pid : constant Rose.Kernel.Processes.Process_Id :=
                     Rose.Kernel.Processes.Current_Process_Id;
   begin
      case Cap.Header.Endpoint is
         when Identity_Map_Page =>
            declare
               Physical_Page : constant Physical_Page_Address :=
                                 Page_Object_Id_To_Physical_Page_Address
                                   (Cap.Payload);
               Virtual_Page  : constant Virtual_Page_Address :=
                                 Virtual_Page_Address (Physical_Page);
            begin
               Rose.Kernel.Processes.Map_Page
                 (Pid       => Pid,
                  Virtual_Page  => Virtual_Page,
                  Physical_Page => Physical_Page,
                  Readable      => True,
                  Writable      => True,
                  Executable    => False,
                  User          => True);
            end;

            Params.Control.Flags :=
              (Rose.Invocation.Reply => True, others => False);

            Rose.Kernel.Processes.Set_Current_State
              (Pid, Rose.Kernel.Processes.Ready);

         when others =>
            null;
      end case;

   end Handle;

end Rose.Kernel.Capabilities.Pages;

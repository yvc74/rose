with Rose.Capabilities;

package Scan is

   Create_Endpoint_Cap : constant Rose.Capabilities.Capability := 1;
   Take_Next_Cap       : constant Rose.Capabilities.Capability := 2;

   Console_Cap         : Rose.Capabilities.Capability;
   Block_Device_Cap    : Rose.Capabilities.Capability;

end Scan;

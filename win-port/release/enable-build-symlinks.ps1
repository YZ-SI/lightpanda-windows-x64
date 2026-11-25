Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class LightpandaBuildToken {
  [StructLayout(LayoutKind.Sequential)] private struct Privilege {
    public uint Count;
    public long Luid;
    public uint Attributes;
  }
  [StructLayout(LayoutKind.Sequential, Pack = 4)] private struct PackedPrivilege {
    public uint Count;
    public long Luid;
    public uint Attributes;
  }
  [DllImport("kernel32.dll")] private static extern IntPtr GetCurrentProcess();
  [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);
  [DllImport("advapi32.dll", SetLastError = true)] private static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
  [DllImport("advapi32.dll", EntryPoint = "LookupPrivilegeValueW", CharSet = CharSet.Unicode, SetLastError = true)]
  private static extern bool LookupPrivilegeValue(string system, string name, out long luid);
  [DllImport("advapi32.dll", SetLastError = true)]
  private static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, ref PackedPrivilege privileges, uint size, IntPtr prev, IntPtr returned);
  public static void EnableSymbolicLinks() {
    if (!OpenProcessToken(GetCurrentProcess(), 0x28, out var token))
      throw new Win32Exception(Marshal.GetLastWin32Error());
    try {
      if (!LookupPrivilegeValue(null, "SeCreateSymbolicLinkPrivilege", out var luid))
        throw new Win32Exception(Marshal.GetLastWin32Error());
      var privilege = new PackedPrivilege { Count = 1, Luid = luid, Attributes = 2 };
      var result = AdjustTokenPrivileges(token, false, ref privilege, 0, IntPtr.Zero, IntPtr.Zero);
      var error = Marshal.GetLastWin32Error();
      if (!result || error != 0)
        throw new Win32Exception(error);
    } finally {
      CloseHandle(token);
    }
  }
}
"@
[LightpandaBuildToken]::EnableSymbolicLinks()

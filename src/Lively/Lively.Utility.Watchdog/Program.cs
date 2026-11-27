using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;

namespace Lively.Utility.Watchdog
{
    /// <summary>
    /// Kills external application type wallpapers in the event lively main pgm is killed by taskmanager/other programs.
    /// <br>Commands:</br> 
    /// <br>ADD/RMV {pid} - Add/remove program from watchlist.</br>
    /// <br>CLR - Clear watchlist.</br>
    /// </summary>
    public class Program
    {
        private static readonly List<int> activePrograms = new List<int>();

        static void Main(string[] args)
        {
            int parentProcessId;
            Process parentProcess;

            if (args.Length == 1)
            {
                try
                {
                    parentProcessId = Convert.ToInt32(args[0], 10);
                }
                catch
                {
                    //ERROR: converting toint
                    return;
                }
            }
            else
            {
                //"Incorrent no of arguments."
                return;
            }

            try
            {
                parentProcess = Process.GetProcessById(parentProcessId);
            }
            catch
            {
                //getting processname failure!
                return;
            }

            // Vibe Loop: remember where the core is installed so that only *this* installation's UI is terminated below.
            // Path must be captured while the parent is still alive.
            var coreDirectory = GetProcessDirectory(parentProcess.Id);

            StdInListener();
            parentProcess.WaitForExit();

            foreach (var item in activePrograms)
            {
                try
                {
                    Process.GetProcessById(item).Kill();
                }
                catch { }
            }

            // Upstream killed every process named "Lively.UI.WinUI" system-wide, which would also close the UI of a
            // separately installed Lively Wallpaper (same UI executable name). Restrict to UI processes belonging to this install.
            foreach (var item in Process.GetProcessesByName("Lively.UI.WinUI"))
            {
                try
                {
                    if (IsSameInstallation(coreDirectory, GetProcessDirectory(item.Id)))
                        item.Kill();
                }
                catch { }
            }

            //force refresh desktop.
            _ = SystemParametersInfo(SPI_SETDESKWALLPAPER, 0, null, SPIF_UPDATEINIFILE);
        }


        /// <summary>
        /// std I/O redirect.
        /// </summary>
        private static async void StdInListener()
        {
            try
            {
                await Task.Run(async () =>
                {
                    while (true)
                    {
                        var msg = await Console.In.ReadLineAsync();
                        var args = msg.Split(' ');
                        if (args[0].Equals("CLR", StringComparison.OrdinalIgnoreCase))
                        {
                            activePrograms.Clear();
                        }
                        else if (args[0].Equals("ADD", StringComparison.OrdinalIgnoreCase))
                        {
                            if (int.TryParse(args[1], out int value))
                            {
                                activePrograms.Add(value);
                            }
                        }
                        else if (args[0].Equals("RMV", StringComparison.OrdinalIgnoreCase))
                        {
                            if (int.TryParse(args[1], out int value))
                            {
                                _ = activePrograms.Remove(value);
                            }
                        }
                    }
                });
            }
            catch { }
        }

        /// <summary>
        /// UI lives in "&lt;core&gt;\plugins\UI" (installer build) or in the parent folder of the core (MSIX build: core in "Build\").
        /// </summary>
        private static bool IsSameInstallation(string coreDirectory, string uiDirectory)
        {
            if (string.IsNullOrEmpty(coreDirectory) || string.IsNullOrEmpty(uiDirectory))
                return false;

            var core = coreDirectory.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            var ui = uiDirectory.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            var coreParent = Path.GetDirectoryName(coreDirectory.TrimEnd(Path.DirectorySeparatorChar));
            return ui.StartsWith(core, StringComparison.OrdinalIgnoreCase) ||
                (coreParent != null && string.Equals(ui, coreParent.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase));
        }

        private static string GetProcessDirectory(int processId)
        {
            var handle = IntPtr.Zero;
            try
            {
                handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, processId);
                if (handle == IntPtr.Zero)
                    return null;

                var buffer = new StringBuilder(1024);
                var size = buffer.Capacity;
                return QueryFullProcessImageName(handle, 0, buffer, ref size) ? Path.GetDirectoryName(buffer.ToString()) : null;
            }
            catch
            {
                return null;
            }
            finally
            {
                if (handle != IntPtr.Zero)
                    CloseHandle(handle);
            }
        }

        private const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool QueryFullProcessImageName(IntPtr hProcess, uint dwFlags, StringBuilder lpExeName, ref int lpdwSize);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr hObject);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        [return: MarshalAs(UnmanagedType.I4)]
        private static extern Int32 SystemParametersInfo(UInt32 uiAction, UInt32 uiParam, String pvParam, UInt32 fWinIni);
        private static UInt32 SPI_SETDESKWALLPAPER = 20;
        private static UInt32 SPIF_UPDATEINIFILE = 0x1;
    }
}

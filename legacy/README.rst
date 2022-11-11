openvpn-windows-test
====================

Powershell scripts for testing OpenVPN on Windows. The Test-Openvpn.ps1 script
can test OpenVPN in cmd.exe, OpenVPN-GUI and  openvpnserv2. Success and failure
are based on simple ping tests to one or more hosts. A typical use-case for
these scripts is smoke-testing an installer prior to a major release.

The Test-Installer.ps1 script currently tests how OpenVPN reinstalls and full
uninstall/install cycles affect the service states. The script was motivated
by the need to test the changes in openvpn-build pull request #80. Later the
script can be extended to other things and integrated with Test-OpenVPN.ps1.

The Test-Installer.ps1 script will use the management interface to cleanly shut
down OpenVPN instances launched from cmd.exe. Similarly, in OpenVPNService-based
tests, OpenVPN instances are cleanly shut down using exit-events implemented in
OpenVPNService itself. However, there's currently no way to signal OpenVPN GUI
to shut down itself, or the OpenVPN instances it manages.

Using test-openvpn.ps1
======================

Test-Openvpn.ps1 tests only one VPN connection:
::
  Usage: Test-Openvpn.ps1 -Config <openvpn-config-file> -Ping <hosts> [-Openvpn <openvpn-exe>] [-Gui <openvpn-gui-exe>] [-TestCmdexe] [-TestService] [-TestRespawn] [-TestGui] [-Help]
  
  Parameters:
     -Openvpn     Path to openvpn.exe (defaults to C:\Program Files\OpenVPN\bin\openvpn.exe)
     -Gui         Path to openvpn-gui.exe (defaults to C:\Program Files\OpenVPN\bin\openvpn-gui.exe)
     -Config      Path to the OpenVPN configuration file
     -Ping        Target host(s) inside VPN to ping (should succeed). Separate multiple entries
                  with commas.
     -Suspend     Test suspend and resume [UNIMPLEMENTED]
     -TestCmdexe  Test connection from the command-line
     -TestGui     Test OpenVPN-GUI
     -TestService Test openvpnserv2.exe
     -TestRespawn Test if openvpnserv2 is able to respawn a dead connection properly
     -Help        Display this help
  
  Example: .\Test-Openvpn.ps1 -Config "C:\Program Files\OpenVPN\config\company.ovpn" -Ping 192.168.40.7 -TestCmdexe -TestService -TestGui

To verify that the connections do not succeed because of a bug or by accident,
-Ping a fake IP that can only fail.

Note that Windows may prompt for user feedback at certain points, e.g. to allow
connections through the firewall. The answers can typically be cached, so that
the script can run without user interaction.

To test several connections in a row copy `run-sample.ps1 <run-sample.ps1>`_ to
run.ps1 and adapt it to your needs. This way you can verify that your particular
version of OpenVPN works with all of your VPN connections.

Note that right now OpenVPN might mess up IPv6 routes if OpenVPN instances are
killed forcibly, as this script does in most cases. This can cause IPv6 ping
tests to fail after an initial connection.

Scope of the tests
------------------

OpenVPN inside cmd.exe:

Connect -> ping test -> disconnect

OpenVPN GUI:

Connect -> ping test -> disconnect

Openvpnserv2:

Connect -> ping test -> kill openvpn -> openvpnserv2 restart openvpn -> ping test -> disconnect

Warnings
--------

The test-openvpn.ps1 script brutally kills every openvpn.exe and openvpn-gui.exe
process it finds at startup, as well as stops OpenVPNService. As described
above, in OpenVPN GUI tests OpenVPN GUI and the OpenVPN instances it manages
are killled without signaling.

The openvpnserv2-based tests move irrelevant .ovpn files out of the way to the
current working directory before launching the service. After the test the
files are put back where they belong. If the script is stopped in the middle,
some .ovpn files may have to be moved back manually.

While this script seems to work fine, it can potentially cause issues. At
minimum make sure that your VPN configurations are backed up.

Using Test-Installer.ps1
========================

Test-Installer.ps1 is straightforward to use:
::
  Usage: Test-Installer.ps1 -Installer <installer-file> [-Verbose] [-TestUpgrade] [-TestCleanInstall] [-Help]
  
  Parameters:
     -Installer        Path to the OpenVPN installer you wish to test
     -Verbose          Show what is happening, even if there is nothing
                       noteworthy to report
     -TestUpgrade      Test reinstalling on top of old installation
     -TestCleanInstall Test full uninstall -> install cycle
     -Help             Display this help
	 

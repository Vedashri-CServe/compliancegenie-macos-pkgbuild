-- Compiled by build-pkg.sh into "/Applications/Uninstall ComplianceGenie Agent.app"
set appTitle to "ComplianceGenie Agent"
set scriptPath to "/usr/local/compliancegenie/uninstall.sh"

try
	do shell script "test -x " & quoted form of scriptPath
on error
	display dialog "ComplianceGenie Agent does not appear to be installed on this Mac." with title appTitle buttons {"OK"} default button "OK" with icon caution
	return
end try

display dialog "This will remove the ComplianceGenie Agent from this Mac.

This Mac will stop reporting its security status to the ComplianceGenie portal. You will be asked for an administrator password." with title appTitle buttons {"Cancel", "Uninstall"} default button "Cancel" cancel button "Cancel" with icon caution

try
	do shell script quoted form of scriptPath with administrator privileges
	display dialog "ComplianceGenie Agent has been removed." with title appTitle buttons {"OK"} default button "OK" with icon note
on error errMsg number errNum
	if errNum is not -128 then
		display dialog "Uninstall failed: " & errMsg with title appTitle buttons {"OK"} default button "OK" with icon stop
	end if
end try

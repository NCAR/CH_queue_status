#!/usr/bin/perl
use strict;
#use warnings; 

 
my $targetdir = " ";
my $logfilename = " ";

my $tmpdatestamp=`date "+%m%d%y_%R"`;
chomp $tmpdatestamp;

#
# Check for optional arguments - only "-use_qstat_cache" and "-test_mode" are valid
#
my $nArgs = scalar @ARGV;
print "\nnumber of input arguments = $nArgs   (@ARGV) \n";

my $testing_mode = 0;
my $use_qstat_cache = 0; 

use Getopt::Long;
GetOptions( 'use_qstat_cache' => \$use_qstat_cache,
	        'test_mode' => \$testing_mode);
print ("after GetOptions   use_qstat_cache = $use_qstat_cache  testing_mode = $testing_mode \n\n"); 

if ( $nArgs > 0 ) {
	if ($use_qstat_cache == 1) {
        $testing_mode = 1;
        print "Will use existing qstat cache files. \n";
    } 
    if ($testing_mode == 1) {
    	print "Will run in test mode. \n";
    } 
    if (($use_qstat_cache+$testing_mode) == 0) {
    	print "\nInvalid option(s). Only valid options are '-use_qstat_cache'and '-test_mode'.\n";
    	exit;
    }
}


# Set up output file names and directories
#
if ($testing_mode == 1) {
	use Cwd qw(cwd);
	$targetdir = cwd;
	$logfilename = $targetdir . "/" . $tmpdatestamp . ".log";
} else {
	$targetdir = "/glade/u/home/csgteam/scripts/queue_status_ch";
	$logfilename = "/glade/scratch/csgteam/ch_queue_status_logs/" . $tmpdatestamp . ".log";
}

#
# if running in "production" mode send print diagnostics output to $logfilename, otherwise
# just echo to terminal
#
print "\noutput target directory: $targetdir \n";
print "output log file: $logfilename \n\n\n";
open(my $LOG, '>>', $logfilename) or die "Could not open file '$logfilename' $! \n";
select $LOG;
if ($testing_mode == 1) {
	select STDOUT;    # send print output to terminal
}

my $timeout = 60;   # seconds to wait for "qstat" and "pbsnodes" commands to return
#$timeout = 1;      # Short timeout for testing purposes only 

#
# STATUSFILE is a simple text file version of the output html file that will be accessed
# by users with a command script "show_status".
#
open HTMLFILE, ">$targetdir/queues_table_ch.html" or die "Could not open file HTMLFILE $!";
open STATUSFILE, ">$targetdir/show_status.out" or die "Could not open file STATUSFILE $!";

my $qstat_out_len = 0;
my $nodestate_out_len = 0;

my @all_share_queue_reservations;
my @share_queue_reservations;
my @all_reservations;
my @reservations;
my %q;

my $color = "#000000";

#
# generate the files with PBS qstat and pbsnodes command output. These files will be parsed repeatedly
#
eval {
        local $SIG{ALRM} = sub { die "alarm\n" };
        alarm $timeout;
        
        # throttle the demand on the PBS server
        my $sleepcmd = "sleep 10";
        if ($testing_mode == 1) {
        	$sleepcmd = "sleep 1";
        }
        
        if ($use_qstat_cache == 0) {
			`timeout -s SIGKILL $timeout /opt/pbs/default/bin/qstat | grep -vi "job id" | grep ".chadmin" > "$targetdir/qstat.out"`;
			my $noop = `$sleepcmd`;
			`timeout -s SIGKILL $timeout /opt/pbs/default/bin/qstat -t -n -1 | grep ".chadmin" | grep " R "  > "$targetdir/qstat-tn1.out"`;
			$noop = `$sleepcmd`;
			`timeout -s SIGKILL $timeout /opt/pbs/default/bin/pbsnodes -a | grep "state = " | grep -v comment | sort | uniq -c > "$targetdir/nodestate.out"`;
			$noop = `$sleepcmd`;
			`timeout -s SIGKILL $timeout /opt/pbs/default/bin/pbsnodes -a > "$targetdir/pbsnodes-a.out"`;
        }

        $qstat_out_len = `cat $targetdir/qstat.out | wc -l`;
        $nodestate_out_len = `grep state $targetdir/nodestate.out | wc -l`;

        alarm 0;
};


if ($@ | ($nodestate_out_len == 0) | ($qstat_out_len == 0)) {
	# qstat and/or pbsnodes command timed out or did not return anything useful
	if ( ($nodestate_out_len == 0) | ($qstat_out_len == 0) ) { $@ = "alarm\n";}
	die unless $@ eq "alarm\n"; # propagate unexpected errors

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$year += 1900; $mon++;
	my $datestamp = sprintf('%02d:%02d %02d/%02d/%04d',$hour,$min,$mon,$mday,$year);

	print HTMLFILE qq{
	<body>
		<style type="text/css">
			table {
			  width: 600px;
			  border-collapse: collapse;
			  font-family: "Lucida Sans Unicode","Lucida Grande",Verdana,Arial,Helvetica,sans-serif;
			  font-size: 0.75em;
			}
		</style>
			
		<table style="width: 600px; border="2" cellpadding="3">
			<tbody>
				<tr valign="middle">
					<td style="text-align: left;"><img src="https://www.cisl.ucar.edu/uss/resource_status_table/light_red.gif" width="25" /></td>
					<td style="text-align: left;">
						The Cheyenne job scheduling system was not responding as of $datestamp.<br />
						If the problem persists, users will receive email updates through our Notifier service.
					</td>
				</tr>
			</tbody>
		</table>
	};
	close (HTMLFILE);
	
	print STATUSFILE "  \n";
	print STATUSFILE " The Cheyenne job scheduling system was not responding as of $datestamp. \n";
	print STATUSFILE " If the problem persists, users will receive email updates through our Notifier service. \n";
	print STATUSFILE "  \n";
	close (STATUSFILE);
	
	print "\nqstat and/or pbsnodes commands timed out or did not return anything useful\n";
	print "processing was aborted. \n\n";
	
} else {   # PBS commands did not time out so proceed
	
	my $nNodes_free = `cat "$targetdir/nodestate.out" | grep "state = free" | awk '{ print \$1 }'`;
	my @nodes_jobs  = `cat "$targetdir/nodestate.out" | grep "job-exclusive" | grep -v down | grep -v offline | awk '{ print \$1 }'`;
	
	my @nodes_offline  = `/opt/pbs/default/bin/pbsnodes -l | awk '{ print \$1 }'`;
	my $nNodes_offline = scalar @nodes_offline;
	my @nnodes_res     = `cat "$targetdir/nodestate.out" | grep "resv-exclusive" | grep -v "job-exclusive" | awk '{ print \$1 }'`;
	
	my $nNodes_jobs = 0;
	foreach my $nnodes_job (@nodes_jobs) {
		$nNodes_jobs += $nnodes_job;
	}
	
	my $nNodes_resv = 0;
	foreach my $nnodes (@nnodes_res) {
		$nNodes_resv += $nnodes;
	}
	
	print "According to pbsnodes command: \n";
	print "number of nodes free  = $nNodes_free";
	print "number of nodes busy  = $nNodes_jobs \n";
	print "number of nodes offline  = $nNodes_offline \n";
	print "number of nodes reserved = $nNodes_resv \n";
	my $tmp_nodecount = $nNodes_free + $nNodes_jobs + $nNodes_offline + $nNodes_resv;
	print "total number of nodes accounted for by pbsnodes = $tmp_nodecount\n\n";
	
	
	my $run_prem  = `cat "$targetdir/qstat.out" | grep " R premium" | wc -l`;
	my $run_reg   = `cat "$targetdir/qstat.out" | grep " R regular" | wc -l`;
	my $run_econ  = `cat "$targetdir/qstat.out" | grep " R economy" | wc -l`;
	my $run_share = `cat "$targetdir/qstat.out" | grep " R sharex"  | wc -l`;
	my $run_stand = `cat "$targetdir/qstat.out" | grep " R standby" | wc -l`;
	my $run_spec  = `cat "$targetdir/qstat.out" | grep " R special" | wc -l`;
	my $run_amps  = `cat "$targetdir/qstat.out" | grep " R ampsrt"  | wc -l`;
	my $run_sys   = `cat "$targetdir/qstat.out" | grep " R system"  | wc -l`;
	
	my $tot_jobs_running = 0;
	print "\njobs running in regular queue  = $run_reg";     
	print "jobs running in economy queue  = $run_econ";      
	print "jobs running in special queue  = $run_spec";      
	print "jobs running in ampsrt queue   = $run_amps"; 
	print "jobs running in premium queue  = $run_prem";
	print "jobs running in standby queue  = $run_stand";
	print "jobs running in system queue   = $run_sys";
	print "jobs running in share queue    = $run_share";
	
	$tot_jobs_running = $run_prem + $run_reg + $run_econ + $run_stand + $run_spec + $run_amps + $run_sys + $run_share;
	print "number of batch jobs running (not including reservations) = $tot_jobs_running \n\n";
	
	
	@reservations = `/opt/pbs/default/bin/pbs_rstat | grep ' R[0-9][0-9]' | awk '{print \$2}'`;
	print scalar @reservations; print " reservations found \n";
	print @reservations, "\n";

	my $run_resv = 0;
	foreach my $res (@reservations) {
		chomp $res;
		#$run_resv += `cat "$targetdir/qstat.out" | grep $res | grep " R " | wc -l`;
		my $num_running_jobs = `cat "$targetdir/qstat.out" | grep $res | grep " R " | wc -l`;
		chomp $num_running_jobs;
		$run_resv += $num_running_jobs;
		print "reservation $res   jobs running = $num_running_jobs\n";
	}
	print "total number of jobs running in reservations = $run_resv\n";
	
	
	$tot_jobs_running += $run_resv;
	print "\nTotal number of batch jobs = $tot_jobs_running \n\n";

	
	# output the html
	# the loop through the queues also counts the number of users ($q{$queue}[3]) for each queue.
	# the "if" portion of those statements avoids displaying "0" for empty queues.
	
	print HTMLFILE q{
			<body>
			<style type="text/css">
			table {
				width: 600px;
				border-collapse: collapse;
				font-family: "Lucida Sans Unicode","Lucida Grande",Verdana,Arial,Helvetica,sans-serif;
			}
			</style>
	
			<table style="width: 600px; height: 320px;" border="2" cellpadding="3">
			<tbody style="text-align: center">
			<tr $color>
				<td><strong>System</strong></td>
				<td><strong>Queue</strong></td>
				<td><strong>Jobs<br>Running</strong></td>
				<td><strong>Nodes<br>in use</strong></td>
				<td><strong>Jobs<br>Queued</strong></td>
				<td><strong>Jobs<br>Held</strong></td>
				<td><strong>Users</strong></td>
			</tr>
	};
	print STATUSFILE "  \n";
	print STATUSFILE "       Queue      Jobs    Nodes     Jobs     Jobs    Users \n";
	print STATUSFILE "               Running   in use   Queued     Held \n";
	
	# forces a particular order on the queues in the table.
	# inserts "-" in place of blanks/zeros. 
	my @queues = qw(system premium regular economy standby special ampsrt share reserved);
	
	my $total_reservedNodes_run = 0;     # number of reserved nodes currently in use in running jobs
	my $total_reservedNodes_free = 0;  # number of reserved nodes currently NOT in use 
	my $reservations_processed = 0;
	
	my $share_nodesinuse_tot = 0;     # number of shared reserved nodes currently in use in running jobs
	my $nShareNodes_free = 0;      # number of shared reserved nodes currently NOT in use 
	
	my $tot_running_nodes = 0;
	foreach my $queue (@queues) {
			
		$q{$queue}[0] = '-' unless ($q{$queue}[0]);   # number of jobs running in $queue
		$q{$queue}[1] = '-' unless ($q{$queue}[1]);   # number of nodes in running jobs in $queue
		$q{$queue}[2] = '-' unless ($q{$queue}[2]);   # number of jobs queued in $queue
		$q{$queue}[3] = '-' unless ($q{$queue}[3]);   # number of jobs held in $queue
		$q{$queue}[4] = '-' unless ($q{$queue}[4]);   # number of unique users with jobs in $queue
		
		if ($queue =~ m/system|premium|regular|economy|standby|special|ampsrt|share/) {
			my $queue_name = $queue;
			
			$q{$queue}[0] = `cat "$targetdir/qstat.out" | grep $queue_name | grep " R " | wc -l`;
			$q{$queue}[2] = `cat "$targetdir/qstat.out" | grep $queue_name | grep " Q " | wc -l`;
			$q{$queue}[3] = `cat "$targetdir/qstat.out" | grep $queue_name | grep " H " | wc -l`;
			$q{$queue}[4] = `cat "$targetdir/qstat.out" | grep $queue_name | awk '{ print \$3 }' | sort | uniq | wc -l`;  # number of unique users
			print "queue: $queue   number of unique users = $q{$queue}[4]";

			my $queue_node_count = int(`cat "$targetdir/qstat-tn1.out" | grep $queue_name | grep " R " | awk '{SUM += \$6} END { print SUM }'`); 
			if ($queue_name eq "share") {
				$queue_node_count = int(`cat "$targetdir/qstat-tn1.out" | grep shareex | awk '{ print \$12 }' | cut -f 1 -d '/' | sort | uniq | wc -l`);
				my $nShareNodes = int(`cat "$targetdir/pbsnodes-a.out" | grep "Qlist = " | grep -c share`);
				$nShareNodes_free = $nShareNodes - $queue_node_count;
				print "for share queue: queue_node_count = $queue_node_count    nShareNodes = $nShareNodes    nShareNodes_free = $nShareNodes_free \n";
			}
			chomp $queue_node_count;
			print "node count for jobs running in queue $queue = $queue_node_count\n";
			$q{$queue}[1] = $queue_node_count;
			
			$tot_running_nodes += $queue_node_count;
		}  # for system, premium, regular, economy, standby, special, share and ampsrt queues

		# now process reservations  
		# combine all of them and report them as one entry labled "Reservations".
		elsif ($queue eq "reserved") {
			print "\nnumber of nodes accounted for in jobs not in reservations = $tot_running_nodes \n";
			
			my $reserv_jobs  = 0;
			my $reserv_qued  = 0;
			my $reserv_held  = 0;
			my $reserv_users = 0;
			my $nNodes_reservation = 0;  
			my $tot_nNodes_reserved = 0;
			
			foreach my $reserv (@reservations) {
				$reservations_processed = 1;
				my $nNodes_reservation_running = 0;    # number of nodes running in each reservation;
				
				chomp $reserv;
				print "\nprocessing reservation - $reserv\n";
				
				my $full_res_name = $reserv . ".chadmin1";

				# check to see if this reservation is running.  If it isn't then leave the number of reported nodes to 0
				my $reservation_state = `/opt/pbs/default/bin/pbs_rstat -F $full_res_name | grep reserve_state | grep RESV_RUNNING`;
				chomp $reservation_state;
				print "reservation state = --->$reservation_state<---\n";
				
				if ( length($reservation_state) == 0) {
					$nNodes_reservation = 0;
					print "reservation $reserv is not RUNNING - number of nodes in reservation set to 0 \n";
				}
				else {
					$reserv_jobs  += `cat "$targetdir/qstat.out" | grep $reserv | grep " R " | wc -l`;
					$reserv_qued  += `cat "$targetdir/qstat.out" | grep $reserv | grep " Q " | wc -l`;
					$reserv_held  += `cat "$targetdir/qstat.out" | grep $reserv | grep " H " | wc -l`;
					$reserv_users += `cat "$targetdir/qstat.out" | grep $reserv | awk '{ print \$3 }' | sort | uniq | wc -l`;
					
					$nNodes_reservation = `/opt/pbs/default/bin/pbs_rstat -F $full_res_name | grep nodect | awk '{ print \$3 }'`;
					chomp $nNodes_reservation;
					print "number of nodes in reservation $reserv:  $nNodes_reservation \n";

					$tot_nNodes_reserved += $nNodes_reservation;
					print "cumulative number of reserved nodes = $tot_nNodes_reserved \n\n";

					my @joblist = `cat "$targetdir/qstat.out" | grep $reserv | grep " R " | cut -f 1 -d "."`;
					print scalar @joblist, " jobs currently running in reservation $reserv \n";

					my $nodect = 0;
					foreach my $jobno (@joblist) {
						chomp $jobno;
						my $cmd = "grep $jobno '$targetdir/qstat-tn1.out' | awk '{ print \$6 }'";
						$nodect = `$cmd`;
						print "node count for job $jobno in $reserv = $nodect";
						$total_reservedNodes_run += $nodect;
						$tot_running_nodes += $nodect;
						$nNodes_reservation_running += $nodect;
					}
					print " \n";
					
					$total_reservedNodes_free += ($nNodes_reservation - $nNodes_reservation_running);
					print "total number of free reserved nodes = $nNodes_reservation-$nNodes_reservation_running (nNodes_reservation - nNodes_reservation_running) = $total_reservedNodes_free \n";
					
					#are any of the nodes in this reservation down/offline? If so, then reduce total_reservedNodes_free
					my @res_nodes = `/opt/pbs/default/bin/pbs_rstat -F $full_res_name | grep -Eo '(r)[0-9]+(i)[0-9]+(n)[0-9]+'`;
					my %count = ();
					foreach my $rnode (@res_nodes, @nodes_offline) { 
						$count{$rnode}++; 
						if ($count{$rnode}==2) {
							print "   ** found offline node in reservation: $rnode";
							$total_reservedNodes_free--
						}
					}

					print "number of free nodes in reservation $reserv after checking offline nodes = $total_reservedNodes_free \n";
				}  # if reservation is running
				
			}  # for each reservation
			
			$q{$queue}[0] = $reserv_jobs; 
			$q{$queue}[1] = $total_reservedNodes_run; 
			$q{$queue}[2] = $reserv_qued; 
			$q{$queue}[3] = $reserv_held; 
			$q{$queue}[4] = $reserv_users; 
		}  # end special handling for reservations
		print " \n";
		
		
				
	}   # foreach queue - system|premium|regular|economy|standby|special|share|ampsrt and reservations
		
	if ($reservations_processed == 1) {
		print "\ntotal number of nodes accounted for in running batch jobs = $tot_running_nodes \n";
		print "\nDifference between qstat and pbsnodes = ", $nNodes_jobs - $tot_running_nodes;
		if ($nNodes_jobs > $tot_running_nodes) {
			print " (nodes missing from qstat parsing) \n";
		} else {
			print " (excess nodes counted in qstat parsing) \n";
		}
	}
	print " \n";
		
	
	# determine if any queues are completely empty of any jobs - those entries will skipped.
	my $numRows = 18;
	foreach my $queue (@queues) {
		if ( ($q{$queue}[0] + $q{$queue}[2] + $q{$queue}[3]) == 0 ) {  # count number of jobs running, queued or held
			$numRows--;
			print "no jobs found for queue $queue - will not be reported \n";
		}
	}
	
	print HTMLFILE qq{
		 <tr $color>
			<td rowspan="$numRows">Cheyenne<br />
				<img src="https://www.cisl.ucar.edu/uss/resource_status_table/light_green.gif" width="25">
			</td>
		 </tr>
	};
	

	# Proportionally "re-allocate" all missing or excess nodes to the regular and economy queues by
	# values consistent with the average number of nodes per job in each of those queues. Do not
	# adjust the number of running jobs. 
	# Not sure why this even happens - maybe misunderstanding some nuance of qstat.
	# The intent is to avoid confusion/questions if the Total Node Count would not be reported as 4032.
	# Yes, it's a bit of a hack :-)
	 
	my $total_nodes_jobs  = 0;
	foreach my $queue (@queues) {
		$total_nodes_jobs += $q{$queue}[1];
	}
	print "\nTotal number of nodes accounted for in running jobs = $total_nodes_jobs \n";
	
	my $tmp_total_node_count = $total_nodes_jobs + $nNodes_free + $nShareNodes_free + $total_reservedNodes_free + $nNodes_offline;
	print "total number of nodes accounted for = $tmp_total_node_count \n";
	
	if ($tmp_total_node_count != 4032) {
		print "\n\nBegin adjustments for missing or excess nodes .... \n";

		my $node_diff = 4032 - $tmp_total_node_count;
		print "difference in number of nodes accounted for and 4032 = $node_diff \n";
		
		my $reg_econ_nodes = $q{regular}[1] + $q{economy}[1]; 
		chomp $q{regular}[1]; chomp $q{economy}[1]; 
		print "starting number of nodes in regular and economy jobs: $q{regular}[1]  $q{economy}[1] \n";
		
		my $delta_reg_nodes  = (int(0.5 + $node_diff * $q{regular}[1]/$reg_econ_nodes));
		my $delta_econ_nodes = $node_diff - $delta_reg_nodes;
		
		$q{regular}[1] += $delta_reg_nodes;
		$q{economy}[1] += $delta_econ_nodes;
		print "\nadjusted number of nodes for regular queue = $q{regular}[1]    delta = $delta_reg_nodes\n";
		print "adjusted number of nodes for economy queue = $q{economy}[1]    delta = $delta_econ_nodes\n\n\n";
	}
	
	
	foreach my $queue (@queues) {		
		if ( ($q{$queue}[0] + $q{$queue}[2] + $q{$queue}[3]) > 0 ) {
			print HTMLFILE qq{
				<tr $color>
					<td>$queue</td> 
					<td>$q{$queue}[0]</td>       <!--- number of jobs running            -->
					<td>$q{$queue}[1]</td>       <!--- number of nodes in running jobs   -->
					<td>$q{$queue}[2]</td>       <!--- number of jobs queued             -->
					<td>$q{$queue}[3]</td>       <!--- number of jobs held               -->
					<td>$q{$queue}[4]</td>       <!--- number of users w/ jobs in queue  -->
				</tr>
			};
			printf STATUSFILE "%12s %9d %8d %8d %8d %8d \n", $queue, $q{$queue}[0], $q{$queue}[1], $q{$queue}[2], $q{$queue}[3], $q{$queue}[4];
		}
	}
	
	my $total_jobs   = 0;
	my $total_nodes  = 0;
	my $total_queued = 0;
	my $total_held   = 0;
	my $total_users  = 0;
	
	foreach my $queue (@queues) {
		$total_jobs   += $q{$queue}[0];
		$total_nodes  += $q{$queue}[1];
		$total_queued += $q{$queue}[2];
		$total_held   += $q{$queue}[3];
		$total_users  += $q{$queue}[4];
	}
	
	print HTMLFILE qq{
			<tr $color>
				<td><strong>Totals</strong></td>
				<td><strong> $total_jobs </strong></td>
				<td><strong> $total_nodes </strong></td>
				<td><strong> $total_queued </strong></td>
				<td><strong> $total_held </strong></td>
				<td><strong> $total_users </strong></td>
			</tr>
			};
	printf STATUSFILE "---------------------------------------------------------- \n";
	printf STATUSFILE "      Totals ";
	printf STATUSFILE "%9d %8d %8d %8d %8d \n\n", $total_jobs, $total_nodes, $total_queued, $total_held, $total_users;

	
	my $Total_Node_Count = $nNodes_free + $total_nodes + $nNodes_offline + $nShareNodes_free + $total_reservedNodes_free;
	
	
	# Add the "Remaining Nodes" table.  Assuming that both the number of free nodes and the number 
	# of nodes allocated for the share queue but not in use will always be greater than zero.
	print HTMLFILE qq{
		<tr bgcolor="#D3D3D3">
			<td colspan="6"; style='border-bottom:none'>  </td>
			<!-- td colspan="6">  </td -->
		</tr>
		<tr $color>
			<td colspan="1"; style='border-bottom:none;border-top:none'; bgcolor="#D3D3D3">  </td>
			<td colspan="2"><font size="2"><strong>Remaining Nodes</strong></font></td>
			<td colspan="3"; style='border-bottom:none;border-top:none'; bgcolor="#D3D3D3">  </td>
		</tr>
		<tr $color>
			<td colspan="1"; style='border-bottom:none;border-top:none'; bgcolor="#D3D3D3"> </td>
			<td rowspan="1">Free</td>
			<td colspan="1"> $nNodes_free </td>
			<td colspan="3"; style='border-bottom:none;border-top:none'; bgcolor="#D3D3D3">  </td>
		 </tr>
		 <tr $color>
		 	<td colspan="1"; style='border-bottom:none;border-top:none'; bgcolor="#D3D3D3"> </td>
			<td rowspan="1">Shared</td>
			<td colspan="1"> $nShareNodes_free </td>
			<td colspan="3"; style='border-bottom:none;border-top:none'; bgcolor="#D3D3D3">  </td>
		 </tr>
	};
	
	printf STATUSFILE "Remaining Nodes: \n"; 
	printf STATUSFILE "           Free %5d \n", $nNodes_free;
	printf STATUSFILE "         Shared %5d \n", $nShareNodes_free;
	
	if ($total_reservedNodes_free > 0) {
		print HTMLFILE qq{
		 <tr $color>
		 	<td colspan="1"; style='border-bottom:none;border-top:none'; bgcolor="#D3D3D3"> </td>
			<td rowspan="1">Reserved</td>
			<td colspan="1"> $total_reservedNodes_free </td>
			<td colspan="3"; style='border-bottom:none;border-top:none'; bgcolor="#D3D3D3">  </td>
		 </tr>
		};
		printf STATUSFILE "       Reserved %5d \n", $total_reservedNodes_free;
	}
	
	print HTMLFILE qq{	 
		 <tr $color>
		 	<td colspan="1"; style='border-bottom:none;border-top:none'; bgcolor="#D3D3D3"> </td>
			<td rowspan="1">Down/Offline</td>
			<td colspan="1"> <font color="#ff0000"> $nNodes_offline </font></td>
			<td colspan="3"; style='border-bottom:none;border-top:none'; bgcolor="#D3D3D3">  </td>
		 </tr>
		 
		 <tr $color>
		 	<td colspan="1"; style='border-bottom:none;border-top:none'; bgcolor="#D3D3D3"> </td>
			<td rowspan="1"> <font size="2"> <strong>Total Nodes</strong> </font> </td>
			<td colspan="1"> <strong> $Total_Node_Count </strong> </td> 
			<td colspan="3"; style='border-bottom:none;border-top:none'; bgcolor="#D3D3D3">  </td>
		 </tr>
	};
	printf STATUSFILE "   Down/Offline %5d \n\n", $nNodes_offline;

			
	my $datestamp=`date "+%l:%M %P %Z %a %b %e %Y"`;   # used for display in HTML table
	print HTMLFILE qq{
			<tr>
				<td colspan="7">Updated $datestamp</td>
			</tr>
			</tbody>
			</table>
	};
	#printf STATUSFILE "Updated  %s \n\n", $datestamp;
	
	close (HTMLFILE);
	close (STATUSFILE);
	select STDOUT;

	if ($testing_mode == 0) { 
		my $cmd = "rm -f $logfilename";
#		my $noopt = `$cmd`;
	}

}


# CH_queue_status
This Perl script  generates an html table showing the current node and batch queue usage on Cheyenne.
The script is executed every 5 minutes by 'csgteam' in a cron job.
The output html table is written to /glade/u/home/csgteam/scripts/queue_status_ch/queues_table_ch.html 
and embedded in the CISL Resource Status page, https://www2.cisl.ucar.edu/user-support/cisl-resource-status

# Usage
For typical production execution:
/glade/p/CSG/queue_status_ch/ch_resource_status.pl

There are two optional parameters, "use_qstat_cache" and "test_mode", that were added to aid in
development and debugging.
/glade/p/CSG/queue_status_ch/ch_resource_status.pl -test_mode
Dumps print output to terminal and writes output files to the local working directory. There is a
known side effect using this where an empty output log file is generated.

/glade/p/CSG/queue_status_ch/ch_resource_status.pl -use_qstat_cache
makes use of existing files, "qstat.out", "qstat-tn1.out" and "nodestate.out" to reduce queries
against the PBS database. This also turns on test mode.

# Output files
In addition to "queues_table_ch.html" 4 other files are re-generated on each execution.        
   File Name _______________ Command      
   qstat.out ________________ /opt/pbs/default/bin/qstat | grep -vi "job id" | grep ".chadmin"        
   qstat-tn1.out ____________ /opt/pbs/default/bin/qstat -t -n -1 | grep ".chadmin" | grep " R "           
   nodestate.out ___________ /opt/pbs/default/bin/pbsnodes -a | grep state | grep -v comment | sort | uniq -c           
   show_status.out* ________ text file that mirrors queues_table_ch.html           
   
   *CSG will provide users with a script that will echo "show_status.out" for access to the same information.        

# Example output html table
![alt text](https://github.com/NCAR/CH_queue_status/blob/master/CH_resource_status_table.PNG "Example table")

:: fio_script.bat
:: Run 108 Disk in fio
:: 2020-07-08T09:02:04

:: Get Date & Time 
set hh=%time:~0,2%
if "%time:~0,1%"==" " set hh=0%hh:~1,1%
set dt=%date:~0,4%-%date:~5,2%-%date:~8,2%_%hh%%time:~3,2%%time:~6,2%

:: Remove old fio
echo. > test.fio
echo. > test.log
del *.fio
del *.log

:: Create fio results_%dt%.csv
echo terse_version_3;fio_version;jobname;groupid;error;read_kb;read_bandwidth;read_iops;read_runtime_ms;read_slat_min;read_slat_max;read_slat_mean;read_slat_dev;read_clat_min;read_clat_max;read_clat_mean;read_clat_dev;read_clat_pct01;read_clat_pct02;read_clat_pct03;read_clat_pct04;read_clat_pct05;read_clat_pct06;read_clat_pct07;read_clat_pct08;read_clat_pct09;read_clat_pct10;read_clat_pct11;read_clat_pct12;read_clat_pct13;read_clat_pct14;read_clat_pct15;read_clat_pct16;read_clat_pct17;read_clat_pct18;read_clat_pct19;read_clat_pct20;read_tlat_min;read_lat_max;read_lat_mean;read_lat_dev;read_bw_min;read_bw_max;read_bw_agg_pct;read_bw_mean;read_bw_dev;write_kb;write_bandwidth;write_iops;write_runtime_ms;write_slat_min;write_slat_max;write_slat_mean;write_slat_dev;write_clat_min;write_clat_max;write_clat_mean;write_clat_dev;write_clat_pct01;write_clat_pct02;write_clat_pct03;write_clat_pct04;write_clat_pct05;write_clat_pct06;write_clat_pct07;write_clat_pct08;write_clat_pct09;write_clat_pct10;write_clat_pct11;write_clat_pct12;write_clat_pct13;write_clat_pct14;write_clat_pct15;write_clat_pct16;write_clat_pct17;write_clat_pct18;write_clat_pct19;write_clat_pct20;write_tlat_min;write_lat_max;write_lat_mean;write_lat_dev;write_bw_min;write_bw_max;write_bw_agg_pct;write_bw_mean;write_bw_dev;cpu_user;cpu_sys;cpu_csw;cpu_mjf;cpu_minf;iodepth_1;iodepth_2;iodepth_4;iodepth_8;iodepth_16;iodepth_32;iodepth_64;lat_2us;lat_4us;lat_10us;lat_20us;lat_50us;lat_100us;lat_250us;lat_500us;lat_750us;lat_1000us;lat_2ms;lat_4ms;lat_10ms;lat_20ms;lat_50ms;lat_100ms;lat_250ms;lat_500ms;lat_750ms;lat_1000ms;lat_2000ms;lat_over_2000ms;disk_name;disk_read_iops;disk_write_iops;disk_read_merges;disk_write_merges;disk_read_ticks;write_ticks;disk_queue_time;disk_util > results_%dt%.csv

:: Generate fio config
@ECHO OFF
set rtime=180
set bs_list=4 8 16 32 64 128 256 512
set rw_list=read write
:: set QD_list=1 2 4 8 16 32 64 128 256 512
set QD_list=1
set NJ_list=1 2 3 4 5 6 7 8 9 10

for %%b in (%bs_list%) do (

    for %%r in (%rw_list%) do (
 
        for %%q in (%QD_list%) do (

            for %%n in (%NJ_list%) do (

                echo [global]        >> %%bK_%%r_QD%%q_NJ%%n.fio
                echo ioengine=psync  >> %%bK_%%r_QD%%q_NJ%%n.fio
                echo thread          >> %%bK_%%r_QD%%q_NJ%%n.fio
                echo bs=%%bk         >> %%bK_%%r_QD%%q_NJ%%n.fio
                echo rw=%%r          >> %%bK_%%r_QD%%q_NJ%%n.fio
                echo iodepth=%%q     >> %%bK_%%r_QD%%q_NJ%%n.fio
                echo numjobs=%%n     >> %%bK_%%r_QD%%q_NJ%%n.fio
                echo time_based      >> %%bK_%%r_QD%%q_NJ%%n.fio
                echo runtime=%rtime% >> %%bK_%%r_QD%%q_NJ%%n.fio
                echo group_reporting >> %%bK_%%r_QD%%q_NJ%%n.fio
   
                for /F "tokens=1,2,3,4,5,6" %%A in ('"wmic diskdrive list brief | findstr /c:"SCSI Disk Device""') DO ( 
                    echo [%%bK_%%r_QD%%q_NJ%%n]  >> %%bK_%%r_QD%%q_NJ%%n.fio
                    echo filename=%%F            >> %%bK_%%r_QD%%q_NJ%%n.fio
                )

                fio %%bK_%%r_QD%%q_NJ%%n.fio --output-format=terse --output=%%bK_%%r_QD%%q_NJ%%n.log
                type %%bK_%%r_QD%%q_NJ%%n.log    >> results_%dt%.csv
            )
        )
    )
)

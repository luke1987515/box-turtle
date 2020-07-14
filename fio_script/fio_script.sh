#!/bin/bash
# fio_script.bat
# Run Disk in fio
# 2020-07-14T15:27:29+08:00

# Get Date & Time
dt=$(date '+%Y-%m-%d_%H%M%S')

# Remove old fio
rm -f *.fio
rm -f *.log

# Create fio results_%dt%.csv
echo "terse_version_3;fio_version;jobname;groupid;error;read_kb;read_bandwidth;read_iops;read_runtime_ms;read_slat_min;read_slat_max;read_slat_mean;read_slat_dev;read_clat_min;read_clat_max;read_clat_mean;read_clat_dev;read_clat_pct01;read_clat_pct02;read_clat_pct03;read_clat_pct04;read_clat_pct05;read_clat_pct06;read_clat_pct07;read_clat_pct08;read_clat_pct09;read_clat_pct10;read_clat_pct11;read_clat_pct12;read_clat_pct13;read_clat_pct14;read_clat_pct15;read_clat_pct16;read_clat_pct17;read_clat_pct18;read_clat_pct19;read_clat_pct20;read_tlat_min;read_lat_max;read_lat_mean;read_lat_dev;read_bw_min;read_bw_max;read_bw_agg_pct;read_bw_mean;read_bw_dev;write_kb;write_bandwidth;write_iops;write_runtime_ms;write_slat_min;write_slat_max;write_slat_mean;write_slat_dev;write_clat_min;write_clat_max;write_clat_mean;write_clat_dev;write_clat_pct01;write_clat_pct02;write_clat_pct03;write_clat_pct04;write_clat_pct05;write_clat_pct06;write_clat_pct07;write_clat_pct08;write_clat_pct09;write_clat_pct10;write_clat_pct11;write_clat_pct12;write_clat_pct13;write_clat_pct14;write_clat_pct15;write_clat_pct16;write_clat_pct17;write_clat_pct18;write_clat_pct19;write_clat_pct20;write_tlat_min;write_lat_max;write_lat_mean;write_lat_dev;write_bw_min;write_bw_max;write_bw_agg_pct;write_bw_mean;write_bw_dev;cpu_user;cpu_sys;cpu_csw;cpu_mjf;cpu_minf;iodepth_1;iodepth_2;iodepth_4;iodepth_8;iodepth_16;iodepth_32;iodepth_64;lat_2us;lat_4us;lat_10us;lat_20us;lat_50us;lat_100us;lat_250us;lat_500us;lat_750us;lat_1000us;lat_2ms;lat_4ms;lat_10ms;lat_20ms;lat_50ms;lat_100ms;lat_250ms;lat_500ms;lat_750ms;lat_1000ms;lat_2000ms;lat_over_2000ms;disk_name;disk_read_iops;disk_write_iops;disk_read_merges;disk_write_merges;disk_read_ticks;write_ticks;disk_queue_time;disk_util " > results_${dt}.csv

# Generate device list
lsblk | awk '{print $1}' > dev_list.log
sed -i '/NAME/d' dev_list.log
sed -i '/sda/d' dev_list.log
sed -i '/loop/d' dev_list.log
sed -i '/sr0/d' dev_list.log

# Generate fio config
rtime=180
bs_list="4 8 16 32 64 128 256 512"
rw_list="read write"
# QD_list="1 2 4 8 16 32 64 128 256 512"
QD_list="1 2 4 8 16 32 64 128 256 512"
NJ_list="1 2 4 8 16"

for bs in ${bs_list}; do 
    for rw in ${rw_list}; do
        for QD in ${QD_list}; do
            for NJ in ${NJ_list}; do
             
                echo [global]         >> ${bs}K_${rw}_QD${QD}_NJ${NJ}.fio
                echo ioengine=psync   >> ${bs}K_${rw}_QD${QD}_NJ${NJ}.fio
                echo thread           >> ${bs}K_${rw}_QD${QD}_NJ${NJ}.fio
                echo bs=${bs}k        >> ${bs}K_${rw}_QD${QD}_NJ${NJ}.fio
                echo rw=${rw}         >> ${bs}K_${rw}_QD${QD}_NJ${NJ}.fio
                echo iodepth=${QD}    >> ${bs}K_${rw}_QD${QD}_NJ${NJ}.fio
                echo numjobs=${NJ}    >> ${bs}K_${rw}_QD${QD}_NJ${NJ}.fio
                echo time_based       >> ${bs}K_${rw}_QD${QD}_NJ${NJ}.fio
                echo runtime=${rtime} >> ${bs}K_${rw}_QD${QD}_NJ${NJ}.fio
                echo group_reporting  >> ${bs}K_${rw}_QD${QD}_NJ${NJ}.fio
                
                for device in $(cat dev_list.log); do
                    echo [${bs}K_${rw}_QD${QD}_NJ${NJ}] >> ${bs}K_${rw}_QD${QD}_NJ${NJ}.fio
                    echo filename=/dev/${device}        >> ${bs}K_${rw}_QD${QD}_NJ${NJ}.fio
                done

                fio ${bs}K_${rw}_QD${QD}_NJ${NJ}.fio --output-format=terse --output=${bs}K_${rw}_QD${QD}_NJ${NJ}.log
                cat ${bs}K_${rw}_QD${QD}_NJ${NJ}.log    >> results_%dt%.csv
                
            done
        done
    done
done
#!/bin/bash
partitionspec="-p cobey"
covidspec="-p broadwl --qos=covid-19 --account=covid-19"

export ncores=28
export maxjobs=28
export output_dir='mifs_debug/'

export region_to_test=1
job1=$(sbatch ${partitionspec} --array=1 --export=ALL 1.run_mif.sbatch)

export region_to_test=2
job2=$(sbatch ${partitionspec} --array=1-4 --export=ALL 1.run_mif.sbatch)

export region_to_test=3
job3=$(sbatch ${partitionspec} --array=1-4 --export=ALL 1.run_mif.sbatch)

export region_to_test=4
job4=$(sbatch ${covidspec} --array=1-4 --export=ALL 1.run_mif.sbatch)

export region_to_test=5
job5=$(sbatch -p broadwl-lc --array=1-4 --export=ALL 1.run_mif.sbatch)

job6=$(sbatch ${partitionspec} --dependency=${job1##* },${job2##* },${job3##* },${job4##* },${job5##* } --export=ALL 2.run_aggregate_points.sbatch)

export ncores=28
export maxjobs=250
job7=$(sbatch ${partitionspec} --dependency=${job6##* } --array=1-14 --export=ALL 3.run_pfilter_around_mle.sbatch)
job8=$(sbatch -p broadwl-lc --dependency=${job6##* } --array=15-20 --export=ALL 3.run_pfilter_around_mle.sbatch)
job9=$(sbatch ${covidspec} --dependency=${job6##* } --array=21-50 --export=ALL 3.run_pfilter_around_mle.sbatch)

sbatch ${partitionspec} --dependency=${job7##* },${job8##* },${job9##* } --export ALL 4.run_final_aggregate.sbatch
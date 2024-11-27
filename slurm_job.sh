#!/bin/bash

#SBATCH --job-name treponema
#SBATCH --nodes=10
#SBATCH --cpus-per-task=16
#SBATCH --time=03:00:00
#SBATCH --mem-per-cpu=5g

snakemake --use-singularity --cores 160 --rerun-incomplete --keep-going

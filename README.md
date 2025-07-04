# Pipelines for the assembly of *Treponema pallidum* genomes
This repository contains three Snakemake pipelines (two reference-based and one partially *de novo*) for the assembly of *Treponema pallidum* genomes from short-read sequencing data. Each directory contains a Snakefile and the corresponding configuration file(s). 

## Reference-based assembly
Steps:
1. Read preprocessing
   
   Adapter trimming (automatic adapter recognition), quality trimming & filtering, deduplication\* & QC. 
   
   \*Deduplication is optional at this point (it is done anyway in step 3), but it speeds up the alignment.
   
   Tool: [fastp](https://academic.oup.com/bioinformatics/article/34/17/i884/5093234)

2. Alignment 
   
   Tool: [bwa](https://github.com/lh3/bwa) mem
3. Duplicate removal
   
   Removes alignment duplicates (reads mapping to the same position, with the same orientation). This is different to the read deduplication in step 1, which only removes reads with the exactly same sequence. It aims to reduce the bias introduced by PCR & sequencing errors.
   
   Tool: [samtools](https://academic.oup.com/gigascience/article/10/2/giab008/6137722) markdup

4. Variant calling
   
   Tool: [bcftools](https://academic.oup.com/gigascience/article/10/2/giab008/6137722) mpileup & call

5. Variant filtering
   
   Filtering based on the PHRED quality score (indicates how likely it is to observe a call purely by chance). 
   
   Tool: [bcftools](https://academic.oup.com/gigascience/article/10/2/giab008/6137722) filter

6. Variant callset QC
   
   Variant count by type, indel length, transition/transversion ratio, etc.
   
   Tool: [gatk](https://gatk.broadinstitute.org/hc/en-us) VariantEval

7. Consensus sequence
   
   Two consensus sequences are generated: one with all variants and the other only with SNPs. 
   
   Tool: [bcftools](https://academic.oup.com/gigascience/article/10/2/giab008/6137722) consensus

## Reference-based assembly with base quality score recalibration
This is an alternative pipeline set up by Simona Skiotyté, which includes a base quality score recalibration step. It uses different tools/parameters than the above pipeline for read preprocessing, alignment deduplication, variant calling & filtering, and consesus sequence generation. It is slower since some of the steps don't allow multi-threading and it uses the reference sequence to patch the regions with low coverage. More details can be found [here](https://github.com/laduplessis/treponema_pallidum_simona).

## (Partially) *De novo* assembly
Steps:
1. Read preprocessing

   Tool: [fastp](https://academic.oup.com/bioinformatics/article/34/17/i884/5093234)

2. *De novo* assembly

   Tool: [SPAdes](https://pmc.ncbi.nlm.nih.gov/articles/PMC3342519/)

3. Reference-assisted scaffolding

   Tool: [Ragout](https://academic.oup.com/bioinformatics/article/30/12/i302/388572)

4. Assembly QC

   Tool: [QUAST](https://academic.oup.com/bioinformatics/article/29/8/1072/228832)

## Usage
Basic usage:
```
snakemake --cores <no. of threads> --use-singularity --rerun-incomplete
```
### Environment
A docker image with all dependencies installed is available at [DockerHub](https://hub.docker.com/r/mneacs/treponema-assembly). Running Snakemake with the `--use-singularity` option should automatically download the docker image (if not already available locally) and use it as runtime environment. If the automatic download fails, pull the image beforehand with:
```
singularity pull docker://mneacs/treponema-assembly:latest
```
and change the singularity parameter in `config.yaml` with the path to the generated .sif file.

### Reference sequence
Within the directory containing the Snakefile, create a `reference` subdirectory to store the reference fasta file and the corresponding index and dictionary files (only for the reference-based pipelines). These can be created with:
```
bwa index <reference.fasta>
samtools dict -o <reference.dict> <reference.fasta>
```
Update the reference name in the config file. For the *de novo* pipeline, also update the name in the Ragout recipe file (`ragout.rcp`). 

### Data
Store the compressed paired-end .fastq files in a directory named `data`, containing a subdirectory for each sample. Within a subdirectory called `<sample_name>`, two files are expected: `<sample_name>_1.fastq.gz` and `<sample_name>_2.fastq.gz`. Unless specified otherwise, Snakemake will try to run the assembly pipeline for all samples found in the the `data` directory. To generate specific file(s), indicate their name(s) in the snakemake command. For example, to generate the consensus sequence for sample `ERR3596791`:
```
snakemake --cores 16 --use-singularity results/ERR3596791/ERR3596791.fasta
```
### Resources
All pipelines use up to 16 threads per sample (this number can be adjusted in the configuration file) and can process multiple samples in parallel if enough threads are provided. An example SLURM setup for processing 10 samples in parallel can be found in `slurm_job.sh`. The reference-based pipeline needs up to 10 minutes/sample (with 16 threads). The de novo assembly might take up to 30 minutes/sample. Some steps are memory-intensive (5 GB per CPU).

## Downstream analysis
The pipeline creates a multi-fasta file containing the consensus sequences of all samples, but these will not be aligned (unless only the SNPs were included). To align consensus sequences containing indels or *de novo* assembled sequences, you can try using [MAFFT](https://academic.oup.com/bib/article/20/4/1160/4106928) or [Mauve](https://pmc.ncbi.nlm.nih.gov/articles/PMC442156/). These are among the few multiple sequence alignment tools capable of aligning genomes larger than 1 Mbp, but they are still limited in the number of sequences that can be aligned. MAFFT is relatively fast and accurate for up to 15 sequences, but totally unusable for more. Mauve goes up to 40, but it takes hours to run and it is not very accurate. 

Example usage:
```
mafft --retree 1 --nwildcard --thread <no. of threads> <input.fasta> > <output.fasta>
```
or
```
progressiveMauve --output=<output.xmfa> <input.fasta>
```
Mauve outputs the alignment in extended multi-fasta format which can be converted to regular fasta using [this script](https://github.com/kjolley/seq_scripts/blob/master/xmfa2fasta.pl).

## Long-read assembly

Steps:
1. Basecalling

Extracts reads from POD5 files and trims sequencing adapters, primers and barcodes (after classifying the reads by barcode). Needs GPU.

Tool: [dorado](https://dorado-docs.readthedocs.io/en/latest/) basecaller
```
srun --gpus 8 --mem-per-cpu 10g --time=02:00:00 dorado basecaller --kit-name SQK-NBD114-96 --trim all --models-directory ./ hac barcode44/ > barcode44.bam
```
2. Demultiplexing

Creates one file per barcode using the classification from the previous step. Outputs FASTQ files.

Tool: [dorado](https://dorado-docs.readthedocs.io/en/latest/) demux
```
dorado demux --no-classify --emit-fastq barcode44.bam -o barcode44_demux
```
3. Read QC

Tool: [nanoQC](https://github.com/wdecoster/nanoQC)
```
nanoQC -o barcode44_nanoQC barcode44.fastq
```
4. Read trimming & filtering

Filters low-quality reads (Q<10) and reads shorter than 1000 bp. Trims the first and last 10 bp out of each read.

Tool: [chopper](https://github.com/wdecoster/chopper)
```
chopper -q 10 -l 1000 --headcrop 10 --tailcrop 10 --threads 32 -i barcode44.fastq > barcode44_trimmed.fastq
```
5. Assembly

Tool: [Flye](https://www.nature.com/articles/s41587-019-0072-8)
```
flye --nano-raw barcode44_trimmed.fastq --out-dir barcode44_flye -t 32
```
6. Assembly QC

Tool: [QUAST](https://academic.oup.com/bioinformatics/article/29/8/1072/228832)
```
quast.py --nanopore barcode44_trimmed.fastq -r CP004011.fasta -o barcode44_quast -t 32 barcode44_flye/assembly.fasta
```
# Nextflow Multi-Entry Workflow Demo

This is a demonstration of how to use multiple entry workflows in Nextflow.

> [!TIP]
> **Conclusion**: Using multiple entry workflows simply increases the maintenance burden. 
In order to use multiple entry workflows with nf-schema, one must either maintain separate schemas
or gate each stage with a parameter. One main.nf and a `stages` parameter suffices. Writing indices
means each stage can be run separately. The input can be configured to read a samplesheet using a
different schema from each stage depending on the value of the `stages` parameter.

## Pipeline Overview

```mermaid
flowchart TB
    %% Inputs
    input_raw["samplesheet.csv<br/>(raw reads)"]
    input_trimmed["samplesheet.csv<br/>(trimmed reads)"]
    genome_fasta["genome.fasta"]
    gtf["genome.gtf"]
    transcript_fasta["transcripts.fa"]

    %% Stage 1: clean_data.nf
    subgraph stage1["clean_data.nf"]
        direction TB
        FASTP["FASTP<br/>trim & QC"]
        WRITE_SS["WRITE_SAMPLESHEET<br/>generate index"]
        FASTP --> WRITE_SS
    end

    %% Stage 2: quant_data.nf
    subgraph stage2["quant_data.nf"]
        direction TB
        SALMON_INDEX["SALMON_INDEX<br/>build index"]
        SALMON_QUANT["SALMON_QUANT<br/>quantification"]
        SALMON_INDEX --> SALMON_QUANT
    end

    %% Outputs
    out_trimmed["results/trimmed/"]
    out_fastp["results/fastp/"]
    out_samplesheet["results/samplesheet.csv"]
    out_salmon["results/salmon/"]

    %% Data flow for clean_data.nf
    input_raw --> FASTP
    FASTP -->|trimmed reads| WRITE_SS
    FASTP --> out_trimmed
    FASTP --> out_fastp
    WRITE_SS --> out_samplesheet

    %% Data flow for quant_data.nf
    input_trimmed -.->|or use output from<br/>clean_data.nf| SALMON_QUANT
    genome_fasta --> SALMON_INDEX
    transcript_fasta --> SALMON_INDEX
    transcript_fasta --> SALMON_QUANT
    gtf --> SALMON_QUANT
    SALMON_QUANT --> out_salmon

    %% Styling
    classDef inputStyle fill:#e1f5ff,stroke:#0077be,stroke-width:2px
    classDef outputStyle fill:#fff4e1,stroke:#ff9800,stroke-width:2px
    classDef processStyle fill:#f0f0f0,stroke:#333,stroke-width:2px

    class input_raw,input_trimmed,genome_fasta,gtf,transcript_fasta inputStyle
    class out_trimmed,out_fastp,out_samplesheet,out_salmon outputStyle
```

**main.nf** runs both stages sequentially: `clean_data.nf` → `quant_data.nf`

Both stages can also be run independently:
- **clean_data.nf**: Produces trimmed reads and a samplesheet for the next stage
- **quant_data.nf**: Can start from trimmed reads (either from `clean_data.nf` or existing data)

## Usage

### All-in-one (main.nf)

Runs trimming and quantification in a single command:

```bash
nextflow run main.nf \
    -profile docker \
    --input            samplesheet.csv \
    --outdir           results \
    --genome_fasta     path/to/genome.fa \
    --gtf              path/to/genome.gtf \
    --transcript_fasta path/to/transcripts.fa
```

### Stage 1 only — trimming & QC (clean_data.nf)

Useful when you only need trimmed reads and fastp reports, or want to inspect quality before committing to quantification:

```bash
nextflow run clean_data.nf \
    -profile docker \
    --input  samplesheet.csv \
    --outdir results
```

**Outputs:**
- `results/trimmed/` — trimmed FASTQ files
- `results/fastp/` — JSON and HTML QC reports
- `results/samplesheet.csv` — index for passing to `quant_data.nf`

### Stage 2 only — quantification (quant_data.nf)

Run after trimming, pointing `--input` at the generated samplesheet:

```bash
nextflow run quant_data.nf \
    -profile docker \
    --input            results/samplesheet.csv \
    --outdir           results \
    --genome_fasta     path/to/genome.fa \
    --gtf              path/to/genome.gtf \
    --transcript_fasta path/to/transcripts.fa
```

**Outputs:**
- `results/salmon/` — per-sample Salmon quantification directories

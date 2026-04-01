include { samplesheetToList } from 'plugin/nf-schema'

include { CLEAN_DATA } from "./subworkflows/local/clean_data"

// ---------------------------------------------------------------------------
// Helper process: collects cleaned-read paths into a samplesheet CSV so the
// result can be passed as --input to quant_data.nf.
// Using a process (rather than collectFile in the workflow) means the index
// file is published through the normal output mechanism and is resumable.
// ---------------------------------------------------------------------------
process WRITE_SAMPLESHEET {
    label 'process_single'

    input:
    val rows // list of "sample,fastq_1,fastq_2,strandedness" strings

    output:
    path 'samplesheet.csv', emit: samplesheet

    script:
    def lines = rows.join('\n')
    """
    printf 'sample,fastq_1,fastq_2,strandedness\\n${lines}\\n' > samplesheet.csv
    """

    stub:
    """
    touch samplesheet.csv
    """
}

// ---------------------------------------------------------------------------
// Validate inputs and convert the samplesheet into a reads channel.
// nf-schema checks every row against assets/schemas/schema_input.json before any
// process runs.
// Column order from schema: sample(meta.id), fastq_1, fastq_2, strandedness(meta.strandedness)
// ---------------------------------------------------------------------------
def samplesheet_to_channel(csv) {
    channel.fromList( samplesheetToList( csv, "${projectDir}/assets/schemas/schema_input.json" ) )
        .map { meta, fastq_1, fastq_2 ->
            def reads    = fastq_2 ? [ fastq_1, fastq_2 ] : fastq_1
            def new_meta = meta + [ single_end: !fastq_2 ]
            [ new_meta, reads ]
        }
}

workflow {

    main:
    def ch_reads = samplesheet_to_channel( params.input )

    CLEAN_DATA( ch_reads )

    // Build one row string per sample for the index CSV
    def ch_index_rows = CLEAN_DATA.out.reads
        .map { meta, reads ->
            def r1 = meta.single_end ? reads.toString()    : reads[0].toString()
            def r2 = meta.single_end ? ''                  : reads[1].toString()
            "${meta.id},${r1},${r2},${meta.strandedness}"
        }
        .toList()

    WRITE_SAMPLESHEET( ch_index_rows )

    def ch_trimmed_reads = CLEAN_DATA.out.reads
    def ch_fastp_reports = CLEAN_DATA.out.json.mix( CLEAN_DATA.out.html )
    def ch_samplesheet   = WRITE_SAMPLESHEET.out.samplesheet

    publish:
    trimmed = ch_trimmed_reads
    fastp   = ch_fastp_reports
    index   = ch_samplesheet
}

output {
    trimmed {
        path 'trimmed'
    }
    fastp {
        path 'fastp'
    }
    // The generated samplesheet index is published directly to the root of
    // outdir so it is easy to pass as --input to quant_data.nf:
    //   nextflow run quant_data.nf --input results/samplesheet.csv
    index {
        path '.'
    }
}

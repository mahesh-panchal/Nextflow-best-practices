include { samplesheetToList } from 'plugin/nf-schema'

include { CLEAN_DATA } from "./subworkflows/local/clean_data"
include { QUANT_DATA } from "./subworkflows/local/quant_data"

// ---------------------------------------------------------------------------
// Validate inputs and convert the samplesheet into a reads channel.
// nf-schema checks every row against assets/schemas/schema_input.json before
// any process runs.
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

    QUANT_DATA(
        CLEAN_DATA.out.reads,
        channel.fromPath( params.genome_fasta,     checkIfExists: true ),
        channel.fromPath( params.gtf,              checkIfExists: true ),
        channel.fromPath( params.transcript_fasta, checkIfExists: true )
    )

    def ch_trimmed_reads  = CLEAN_DATA.out.reads
    def ch_fastp_reports  = CLEAN_DATA.out.json.mix( CLEAN_DATA.out.html )
    def ch_salmon_results = QUANT_DATA.out.results

    publish:
    trimmed = ch_trimmed_reads
    fastp   = ch_fastp_reports
    salmon  = ch_salmon_results
}

output {
    trimmed {
        path 'trimmed'
    }
    fastp {
        path 'fastp'
    }
    salmon {
        path 'salmon'
    }
}

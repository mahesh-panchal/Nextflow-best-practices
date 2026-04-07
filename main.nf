include { samplesheetToList; validateParameters } from 'plugin/nf-schema'

include { CLEAN_DATA } from "./subworkflows/local/clean_data"
include { QUANT_DATA } from "./subworkflows/local/quant_data"

params.stages = ["clean", "quantify"]

workflow {

    main:
    // Validation
    validateParameters()
    def ch_reads = samplesheet_to_channel( params.input )

    if("clean" in params.stages){
        CLEAN_DATA( ch_reads )
    }

    if("quantify" in params.stages){
        QUANT_DATA(
            "clean" in params.stages? CLEAN_DATA.out.reads: ch_reads,
            channel.fromPath( params.genome_fasta,     checkIfExists: true ),
            channel.fromPath( params.gtf,              checkIfExists: true ),
            channel.fromPath( params.transcript_fasta, checkIfExists: true )
        )
    }

    def ch_trimmed_reads  = "clean" in params.stages? CLEAN_DATA.out.reads: channel.empty()
    def ch_fastp_reports  = "clean" in params.stages? CLEAN_DATA.out.json.mix( CLEAN_DATA.out.html ): channel.empty()
    def ch_salmon_results = "quantify" in params.stages? QUANT_DATA.out.results: channel.empty()

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

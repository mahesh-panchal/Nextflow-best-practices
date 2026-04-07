include { samplesheetToList; validateParameters } from 'plugin/nf-schema'

include { QUANT_DATA } from "./subworkflows/local/quant_data"

params.stages = ["quantify"]

workflow {

    main:
    validateParameters()
    def ch_reads = samplesheet_to_channel( params.input )

    QUANT_DATA(
        ch_reads,
        channel.fromPath( params.genome_fasta,     checkIfExists: true ),
        channel.fromPath( params.gtf,              checkIfExists: true ),
        channel.fromPath( params.transcript_fasta, checkIfExists: true )
    )

    def ch_salmon_results    = QUANT_DATA.out.results
    def ch_lib_format_counts = QUANT_DATA.out.lib_format_counts

    publish:
    salmon     = ch_salmon_results
    lib_format = ch_lib_format_counts
}

output {
    salmon {
        path 'salmon'
    }
    lib_format {
        path 'salmon/lib_format_counts'
    }
}

def samplesheet_to_channel(csv) {
    channel.fromList( samplesheetToList( csv, "${projectDir}/assets/schemas/schema_input.json" ) )
        .map { meta, fastq_1, fastq_2 ->
            def reads    = fastq_2 ? [ fastq_1, fastq_2 ] : fastq_1
            def new_meta = meta + [ single_end: !fastq_2 ]
            [ new_meta, reads ]
        }
}

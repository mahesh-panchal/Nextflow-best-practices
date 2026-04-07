include { samplesheetToList; validateParameters } from 'plugin/nf-schema'

include { CLEAN_DATA } from "./subworkflows/local/clean_data"
include { QUANT_DATA } from "./subworkflows/local/quant_data"

params.stages = ["clean", "quantify"]

workflow {

    main:
    // Validation
    validateParameters()
    def ch_reads = samplesheet_to_channel( params.input )

    def ch_trimmed_reads = channel.empty()
    def ch_fastp_reports = channel.empty()
    if("clean" in params.stages){
        CLEAN_DATA( ch_reads )
        // Build dictionary for index
        ch_trimmed_reads = CLEAN_DATA.out.reads
            .map { meta, reads ->
                [
                    sample: meta.id,
                    read1: meta.single_end ? reads : reads.first(),
                    read2: meta.single_end ? ''    : reads.last(),
                    strand: meta.strandedness,
                ]
            }
        ch_fastp_reports = CLEAN_DATA.out.json.mix( CLEAN_DATA.out.html )
    }

    def ch_salmon_results = channel.empty()
    def ch_lib_format_counts = channel.empty()
    if("quantify" in params.stages){
        QUANT_DATA(
            "clean" in params.stages? CLEAN_DATA.out.reads: ch_reads,
            channel.fromPath( params.genome_fasta,     checkIfExists: true ),
            channel.fromPath( params.gtf,              checkIfExists: true ),
            channel.fromPath( params.transcript_fasta, checkIfExists: true )
        )
        ch_salmon_results = QUANT_DATA.out.results
        ch_lib_format_counts = QUANT_DATA.out.lib_format_counts
    }

    publish:
    trimmed    = ch_trimmed_reads
    fastp      = ch_fastp_reports
    salmon     = ch_salmon_results
    lib_format = ch_lib_format_counts
}

output {
    trimmed {
        path 'trimmed'
        index {
            path "cleaned_fastq.csv"
            header true
            sep ","
        }
    }
    fastp {
        path 'fastp'
    }
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

include { samplesheetToList; validateParameters } from 'plugin/nf-schema'

include { CLEAN_DATA } from "./subworkflows/local/clean_data"

// Set stages
params.stages = ["clean"]

workflow {

    main:
    validateParameters()
    def ch_reads = samplesheet_to_channel( params.input )

    CLEAN_DATA( ch_reads )

    def ch_trimmed_reads = CLEAN_DATA.out.reads
        // Build dictionary for index
        .map { meta, reads ->
            [
                sample: meta.id,
                read1: meta.single_end ? reads : reads.first(),
                read2: meta.single_end ? ''    : reads.last(),
                strand: meta.strandedness,
            ]
        }
    def ch_fastp_reports = CLEAN_DATA.out.json.mix( CLEAN_DATA.out.html )

    publish:
    trimmed = ch_trimmed_reads
    fastp   = ch_fastp_reports
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
}

def samplesheet_to_channel(csv) {
    channel.fromList( samplesheetToList( csv, "${projectDir}/assets/schemas/schema_input.json" ) )
        .map { meta, fastq_1, fastq_2 ->
            def reads    = fastq_2 ? [ fastq_1, fastq_2 ] : fastq_1
            def new_meta = meta + [ single_end: !fastq_2 ]
            [ new_meta, reads ]
        }
}

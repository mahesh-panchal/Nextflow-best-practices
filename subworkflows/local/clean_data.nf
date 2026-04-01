include { FASTP } from "../../modules/nf-core/fastp/main"

workflow CLEAN_DATA {

    take:
    reads // channel: [ val(meta), path(reads) ]

    main:
    def ch_versions = channel.empty()

    FASTP(
        reads.map { meta, fastq -> [ meta, fastq, [] ] },  // no adapter_fasta
        false,  // discard_trimmed_pass
        false,  // save_trimmed_fail
        false   // save_merged
    )
    ch_versions = ch_versions.mix( FASTP.out.versions_fastp.first() )

    emit:
    reads    = FASTP.out.reads    // channel: [ val(meta), path(reads) ]
    json     = FASTP.out.json     // channel: [ val(meta), path(json)  ]
    html     = FASTP.out.html     // channel: [ val(meta), path(html)  ]
    versions = ch_versions        // channel: [ val(process), val(tool), val(version) ]
}

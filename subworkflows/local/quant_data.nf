include { SALMON_INDEX } from "../../modules/nf-core/salmon/index/main"
include { SALMON_QUANT } from "../../modules/nf-core/salmon/quant/main"

workflow QUANT_DATA {

    take:
    reads            // channel: [ val(meta), path(reads) ]
    genome_fasta     // path: genome FASTA
    gtf              // path: genome GTF file
    transcript_fasta // path: transcript FASTA

    main:
    def ch_versions = channel.empty()

    SALMON_INDEX( genome_fasta, transcript_fasta )
    ch_versions = ch_versions.mix( SALMON_INDEX.out.versions_salmon.first() )

    SALMON_QUANT(
        reads,
        SALMON_INDEX.out.index,
        gtf,
        transcript_fasta,
        false,  // alignment_mode
        ''      // lib_type — auto-detect from meta.strandedness
    )
    ch_versions = ch_versions.mix( SALMON_QUANT.out.versions_salmon.first() )

    emit:
    results           = SALMON_QUANT.out.results           // channel: [ val(meta), path(quant_dir) ]
    json_info         = SALMON_QUANT.out.json_info         // channel: [ val(meta), path(json) ]
    lib_format_counts = SALMON_QUANT.out.lib_format_counts // channel: [ val(meta), path(json) ]
    versions          = ch_versions                        // channel: [ val(process), val(tool), val(version) ]
}

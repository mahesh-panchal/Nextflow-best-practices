## Module Patching

This pattern enhances the nf-core contributions when you utilise them in your own
pipelines. Patching creates a `.diff` file that tracks your local modifications 
against the original module code.

### When to Use Patches

- Alleviating storage and scheduler constraints
    - Grouping short running tasks
    - Piping between commands
    - Cleaning up temporary files
    - Batch processing

> [IMPORTANT]
> For bug fixes or extending a command-line call, contribute it back to nf-core instead.

### Patching Workflow

#### 1. Install the Module
```bash
nf-core modules install fastp
```

#### 2. Make Your Modifications
Edit `modules/nf-core/fastp/main.nf`:
- Modify the `script:` block
- Update `output:` declarations if needed
- Update `input:` declarations if needed

#### 3. Generate the Patch
```bash
nf-core modules patch fastp
```
This command:
- Compares your version against the cached original
- Creates `modules/nf-core/fastp/fastp.diff`
- Updates `modules.json` with patch metadata
- Locks the module to the current version

#### 4. Test Thoroughly

Consider updating local tests too

```bash
# Run module-specific tests
nf-test tests/modules/nf-core/fastp/

# Test in your pipeline context
nf-test test
```

#### 5. Document Your Changes
Add comments in the script explaining:
- **Why** the patch is necessary
- **What** performance issue it addresses
- **Links** to relevant issues or documentation

### Performance Optimization Patterns

#### 1. Command Chaining & Piping

**Problem:** Sequential processes incur overhead from container startup, I/O operations, and scheduler queue time.

**Solution:** Chain related commands within a single `script:` block.

```groovy
script:
"""
# Before (separate processes):
# Process 1: samtools view
# Process 2: samtools sort  
# Process 3: samtools index

# After (single process):
samtools view -b ${input_bam} \\
    | samtools sort -@ ${task.cpus} -m ${task.memory.toGiga()/task.cpus}G - \\
    | tee ${prefix}.sorted.bam \\
    | samtools index - ${prefix}.sorted.bam.bai

# Keeps data in memory, avoids intermediate files
"""
```

**Impact:** 
- Eliminates container spin-up overhead (3× → 1×)
- Keeps data in RAM buffers vs. writing to networked filesystems
- Reduces scheduler load

**Tradeoff:** Less granular error handling, harder to resume from failures.

#### 2. Aggressive Intermediate Cleanup

**Problem:** Nextflow does not clean `work/` unless directed. Large-scale runs 
can exhaust disk quotas mid-execution, especially if lots of intermediate files 
are symlinked between processes.

**Solution:** Remove intermediate files immediately after consumption.

```groovy
script:
"""
# Decompress and process
gunzip -c ${reads} > temp_reads.fastq

# Use the file
fastp -i temp_reads.fastq -o ${prefix}.trimmed.fastq.gz

# Clean up immediately (while still in script block)
rm temp_reads.fastq

# Alternative: use process substitution to avoid temp files entirely
fastp -i <(gunzip -c ${reads}) -o ${prefix}.trimmed.fastq.gz
"""
```

**Why not `afterScript`?**  
- `afterScript` executes **outside** the container in a separate shell
- Cannot access container-specific paths or handle permission differences

**Best practice:** Use process substitution when possible to avoid creating intermediates entirely.

#### 3. Batch Processing for Scheduler Efficiency

**Problem:** Submitting thousands of short-lived jobs (<2 min) overwhelms cluster schedulers and increases queue wait times.

**Solution:** Modify module to accept file batches and process them in a single job.

```groovy
input:
// Before: tuple val(meta), path(reads)
// After:
tuple val(meta), path(reads) // reads is now a list

script:
def batch_size = reads instanceof List ? reads.size() : 1
"""
# Process multiple samples in parallel within the job
printf '%s\\n' ${reads.join(' ')} \\
    | xargs -P ${task.cpus} -I {} bash -c '
        sample=\$(basename {} .fastq.gz)
        fastp -i {} -o \${sample}.trimmed.fastq.gz \\
            --thread 1 \\
            --json \${sample}.json
    '

# Combine reports
cat *.json > ${meta.id}_batch_report.json
"""
```

**Impact:**
- 5,000 × 30s jobs → 50 × 30min jobs
- Reduces scheduler overhead by 100×
- Better resource utilization (less queue wait time)

**Considerations:**
- Requires upstream channel logic changes (`.buffer()` or `.collate()`)
- More complex error handling
- May need increased memory/time resources

### Advanced Techniques

#### Process Substitution (Recommended)
Treat command output as a file descriptor without writing to disk:

```groovy
"""
# Tool requires a file path but you want to avoid writing uncompressed data
bwa mem ref.fa <(gunzip -c reads_1.fq.gz) <(gunzip -c reads_2.fq.gz) \\
    > aligned.sam

# Saves disk space: 10GB compressed → would be 50GB uncompressed
"""
```

**Limitation:** Tool must support reading from file descriptors (most Unix tools do).

#### Named Pipes (FIFOs)
For tools that strictly require a file path and cannot use STDIN:

```groovy
"""
mkfifo temp.fastq

# Producer: decompress in background
gunzip -c ${reads} > temp.fastq &

# Consumer: read from pipe as if it's a file
some_strict_tool --input temp.fastq --output results.txt

# Cleanup
rm temp.fastq
"""
```

**When to use:** Rare edge case for tools that check file extensions or use `fseek()`.

#### Parallel Decompression
For large compressed files on multi-core systems:

```groovy
"""
# Use pigz instead of gunzip (parallelized)
pigz -p ${task.cpus} -dc ${reads} \\
    | tool --input - --output ${prefix}.out
"""
```

**Requires:** `pigz` installed in container. Consider contributing this improvement upstream.

### Maintenance & Updates

#### Updating a Patched Module
```bash
# Check for updates
nf-core modules update fastp

# The CLI will:
# 1. Attempt to apply your patch to the new version
# 2. Report conflicts if any
# 3. Require manual resolution if patches don't apply cleanly
```

**If conflicts occur:**
1. Inspect `modules/nf-core/fastp/fastp.diff`
2. Manually re-apply changes to the updated module
3. Regenerate patch: `nf-core modules patch fastp`

#### Removing a Patch
```bash
# Remove patch and restore original
nf-core modules patch fastp --remove

# Or manually:
rm modules/nf-core/fastp/fastp.diff
nf-core modules install --force fastp
```

### Example: Complete Patched Module

```groovy
process FASTP_OPTIMIZED {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "biocontainers/fastp:0.23.4"

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path("*.trimmed.fq.gz"), emit: reads
    tuple val(meta), path("*.json")         , emit: json
    path "versions.yml"                     , emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def args = task.ext.args ?: ''
    
    // PATCH: Chain decompression → trimming → recompression in memory
    // Avoids writing 50GB uncompressed FASTQ to networked storage
    // See: https://github.com/YOUR-ORG/pipeline/issues/123
    """
    fastp \\
        -i <(gunzip -c ${reads[0]}) \\
        -I <(gunzip -c ${reads[1]}) \\
        -o ${prefix}_1.trimmed.fq.gz \\
        -O ${prefix}_2.trimmed.fq.gz \\
        --thread ${task.cpus} \\
        --json ${prefix}.fastp.json \\
        $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fastp: \$(fastp --version 2>&1 | sed 's/fastp //g')
    END_VERSIONS
    """
}
```

### Summary

**Patching is powerful but creates maintenance debt.** Use it strategically for:
- Performance bottlenecks at scale

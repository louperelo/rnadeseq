#!/usr/bin/env nextflow
/*
========================================================================================
                         qbicsoftware/rnadeseq
========================================================================================
 qbicsoftware/rnadeseq Analysis Pipeline.
 #### Homepage / Documentation
 https://github.com/qbicsoftware/rnadeseq
----------------------------------------------------------------------------------------
*/


def helpMessage() {
    log.info nfcoreHeader()
    log.info"""

    Usage:

    The typical command for running the pipeline is as follows:

    nextflow run qbicsoftware/rnadeseq --rawcounts 'counts.tsv' --metadata 'metadata.tsv' --design 'design.txt' --contrasts 'contrasts.tsv' -profile docker

    Mandatory arguments:
      --rawcounts                   Raw count table (TSV). Columns are samples and rows are genes.
      --metadata                    Metadata table (TSV). Rows are samples and columns contain sample grouping.
      --model                       Linear model function to calculate the contrasts (TXT). Variable names should be columns in metadata file.
      --contrasts                   Table indicating which contrasts to consider. 1 or 0 for every variable specified in the design. Alternatively you can set the parameter defaultcontrasts
      --species                     Species name. Format example: Hsapiens.
      --project_summary             Project summary file downloaded from the qPortal.
      --multiqc                     multiqc.zip folder containing the multiQC plots and report.
      --versions                    Software_versions.csv generated by the RNAseq pipeline.
      --quote                       Signed copy of the offer.
      -profile                      Configuration profile to use. Can use multiple (comma separated)
                                    Available: conda, docker, singularity, awsbatch, test and more.

    Options:
      --logFCthreshold              Threshold (int) to apply to Log 2 Fold Change to consider a gene as differentially expressed.
      --genelist                    List of genes (one per line) of which to plot heatmaps for normalized counts across all samples.                
      --fastqc                      zip file containing the fastqc reports.

    Other options:
      --outdir                      The output directory where the results will be saved
      --email                       Set this parameter to your e-mail address to get a summary e-mail with details of the run sent to you when the workflow exits
      --maxMultiqcEmailFileSize     Theshold size for MultiQC report to be attached in notification email. If file generated by pipeline exceeds the threshold, it will not be attached (Default: 25MB)
      -name                         Name for the pipeline run. If not specified, Nextflow will automatically generate a random mnemonic.

    AWSBatch options:
      --awsqueue                    The AWSBatch JobQueue that needs to be set when running on AWSBatch
      --awsregion                   The AWS Region for your AWS Batch job to run on
    """.stripIndent()
}

/*
 * SET UP CONFIGURATION VARIABLES
 */

// Show help emssage
if (params.help){
    helpMessage()
    exit 0
}

// Has the run name been specified by the user?
//  this has the bonus effect of catching both -name and --name
custom_runName = params.name
if( !(workflow.runName ==~ /[a-z]+_[a-z]+/) ){
  custom_runName = workflow.runName
}


if( workflow.profile == 'awsbatch') {
  // AWSBatch sanity checking
  if (!params.awsqueue || !params.awsregion) exit 1, "Specify correct --awsqueue and --awsregion parameters on AWSBatch!"
  // Check outdir paths to be S3 buckets if running on AWSBatch
  // related: https://github.com/nextflow-io/nextflow/issues/813
  if (!params.outdir.startsWith('s3:')) exit 1, "Outdir not on S3 - specify S3 Bucket to run on AWSBatch!"
  // Prevent trace files to be stored on S3 since S3 does not support rolling files.
  if (workflow.tracedir.startsWith('s3:')) exit 1, "Specify a local tracedir or run without trace! S3 cannot be used for tracefiles."
}

// Stage config files
ch_multiqc_config = Channel.fromPath(params.multiqc_config)
ch_output_docs = Channel.fromPath("$baseDir/docs/output.md")

/*
 * Create a channel for input  files
 */
 // DESeq2
Channel.fromPath("${params.rawcounts}")
           .ifEmpty{exit 1, "Please provide raw counts file!"}
           .set {ch_counts_file}
Channel.fromPath("${params.metadata}")
           .ifEmpty{exit 1, "Please provide metadata file!"}
           .into { ch_metadata_file_for_deseq2; ch_metadata_file_for_pathway }
Channel.fromPath("${params.quote}")
           .ifEmpty{exit 1, "Please provide a PDF of the signed quote!"}
           .set { ch_quote_file}
Channel.fromPath("${params.model}")
            .ifEmpty{exit 1, "Please provide linear model file!"}
            .into { ch_model_for_deseq2_file; ch_model_for_report_file; ch_model_file_for_pathway}
Channel.fromPath("${params.contrasts}")
            .into { ch_contrasts_for_deseq2_file; ch_contrasts_for_report_file }
Channel.fromPath("${params.project_summary}")
            .ifEmpty{exit 1, "Please provide project summary file!"}
            .set { ch_proj_summary_file }
Channel.fromPath("${params.versions}")
            .ifEmpty{exit 1, "Please provide sofware versions file!"}
            .set { ch_softwareversions_file }
Channel.fromPath("${params.config}")
            .ifEmpty{exit 1, "Please provide config file!"}
            .set { ch_config_file }
Channel.fromPath("${params.multiqc}")
            .ifEmpty{exit 1, "Please provide multiqc.zip folder!"}
            .set { ch_multiqc_file }
Channel.fromPath("${params.genelist}")
            .into { ch_genes_for_deseq2_file; ch_genes_for_report_file }

ch_fastqc_file = file(params.fastqc)

/*
 * Check mandatory parameters
 */
if (!params.species) {
  exit 1, "No species has been specified!"
}


// Header log info
log.info nfcoreHeader()
def summary = [:]
if(workflow.revision) summary['Pipeline Release'] = workflow.revision
summary['Run Name']         = custom_runName ?: workflow.runName
summary['Gene Counts'] = params.rawcounts
summary['Metadata'] = params.metadata
summary['Model'] = params.model
summary['Contrasts'] = params.contrasts
summary['Gene list'] = params.genelist
summary['Project summary file'] = params.project_summary
summary['nf-core/rnaseq software versions'] = params.versions
summary['Report config file'] = params.config
summary['Fastqc reports'] = params.fastqc
summary['Multiqc results'] = params.multiqc
summary['Species'] = params.species
summary['Max Resources']    = "$params.max_memory memory, $params.max_cpus cpus, $params.max_time time per job"
if(workflow.containerEngine) summary['Container'] = "$workflow.containerEngine - $workflow.container"
summary['Output dir']       = params.outdir
summary['Launch dir']       = workflow.launchDir
summary['Working dir']      = workflow.workDir
summary['Script dir']       = workflow.projectDir
summary['User']             = workflow.userName
if(workflow.profile == 'awsbatch'){
   summary['AWS Region']    = params.awsregion
   summary['AWS Queue']     = params.awsqueue
}
summary['Config Profile'] = workflow.profile
if(params.config_profile_description) summary['Config Description'] = params.config_profile_description
if(params.config_profile_contact)     summary['Config Contact']     = params.config_profile_contact
if(params.config_profile_url)         summary['Config URL']         = params.config_profile_url
if(params.email) {
  summary['E-mail Address']  = params.email
  summary['MultiQC maxsize'] = params.maxMultiqcEmailFileSize
}
log.info summary.collect { k,v -> "${k.padRight(18)}: $v" }.join("\n")
log.info "\033[2m----------------------------------------------------\033[0m"

// Check the hostnames against configured profiles
checkHostname()

def create_workflow_summary(summary) {
    def yaml_file = workDir.resolve('workflow_summary_mqc.yaml')
    yaml_file.text  = """
    id: 'qbicsoftware-rnadeseq-summary'
    description: " - this information is collected when the pipeline is started."
    section_name: 'qbicsoftware/rnadeseq Workflow Summary'
    section_href: 'https://github.com/qbicsoftware/rnadeseq'
    plot_type: 'html'
    data: |
        <dl class=\"dl-horizontal\">
${summary.collect { k,v -> "            <dt>$k</dt><dd><samp>${v ?: '<span style=\"color:#999999;\">N/A</a>'}</samp></dd>" }.join("\n")}
        </dl>
    """.stripIndent()

   return yaml_file
}


/*
 * Parse software version numbers
 */
process get_software_versions {
    publishDir "${params.outdir}/pipeline_info", mode: 'copy',
    saveAs: {filename ->
        if (filename.indexOf(".csv") > 0) filename
        else null
    }

    output:
    file 'software_versions_mqc.yaml' into software_versions_yaml
    file "software_versions.tsv"

    script:
    """
    echo $workflow.manifest.version > v_pipeline.txt
    echo $workflow.nextflow.version > v_nextflow.txt
    echo \$(R --version 2>&1) > v_R.txt
    Rscript -e "library(RColorBrewer); write(x=as.character(packageVersion('RColorBrewer')), file='v_rcolorbrewer.txt')"
    Rscript -e "library(reshape2); write(x=as.character(packageVersion('reshape2')), file='v_reshape2.txt')"
    Rscript -e "library(genefilter); write(x=as.character(packageVersion('genefilter')), file='v_genefilter.txt')"
    Rscript -e "library(DESeq2); write(x=as.character(packageVersion('DESeq2')), file='v_deseq2.txt')"
    Rscript -e "library(ggplot2); write(x=as.character(packageVersion('ggplot2')), file='v_ggplot2.txt')"
    Rscript -e "library(plyr); write(x=as.character(packageVersion('plyr')), file='v_plyr.txt')"
    Rscript -e "library(vsn); write(x=as.character(packageVersion('vsn')), file='v_vsn.txt')"
    Rscript -e "library(gplots); write(x=as.character(packageVersion('gplots')), file='v_gplots.txt')"
    Rscript -e "library(pheatmap); write(x=as.character(packageVersion('pheatmap')), file='v_pheatmap.txt')" 
    Rscript -e "library(optparse); write(x=as.character(packageVersion('optparse')), file='v_optparse.txt')"
    Rscript -e "library(svglite); write(x=as.character(packageVersion('svglite')), file='v_svglite.txt')"
    scrape_software_versions.py &> software_versions_mqc.yaml
    """
}

/*
 * STEP 1 - DE analysis
 */
process DESeq2 {
    publishDir "${params.outdir}/DESeq2", mode: 'copy'

    input:
    file(gene_counts) from ch_counts_file
    file(metadata) from ch_metadata_file_for_deseq2
    file(model) from ch_model_for_deseq2_file
    file(contrasts) from ch_contrasts_for_deseq2_file
    file(genelist) from ch_genes_for_deseq2_file

    output:
    file "*.zip" into ch_deseq2_for_report, ch_deseq2_for_pathway

    script:
    def genelistopt = genelist.name != 'NO_FILE' ? "--genelist $genelist" : ''
    def contrastsopt = contrasts.name != 'DEFAULT' ? "--contrasts $contrasts" : ''
    """
    DESeq.v2.7.R --counts $gene_counts --metadata $metadata --design $model --logFCthreshold $params.logFCthreshold $contrastsopt $genelistopt
    zip -r DESeq2.zip DESeq2
    """
}

/*
 * STEP 2 - Pathway analysis
 */

process Pathway_analysis {
    publishDir "${params.outdir}/pathway_analysis", mode: 'copy'

    input:
    file(deseq_output) from ch_deseq2_for_pathway
    file(metadata) from ch_metadata_file_for_pathway
    file(model) from ch_model_file_for_pathway

    output:
    file "*.zip" into ch_gprofiler_for_report

    script:
    """
    unzip $deseq_output
    gProfileR.R --dirContrasts 'DESeq2/DE_genes_tables/' --metadata $metadata \
    --model $model --normCounts 'DESeq2/gene_counts_tables/rlog_transformed_gene_counts.tsv' \
    --species $params.species
    zip -r gProfileR.zip gProfileR/
    """
}

/*
 * STEP 3 - RNAseq Report
 */
process Report {
    publishDir "${params.outdir}/report", mode: 'copy'

    input:
    file(proj_summary) from ch_proj_summary_file
    file(softwareversions) from ch_softwareversions_file
    file(model) from ch_model_for_report_file
    file(config) from ch_config_file
    file(contrasts) from ch_contrasts_for_report_file
    file(fastqc) from ch_fastqc_file
    file(deseq2) from ch_deseq2_for_report
    file(multiqc) from ch_multiqc_file
    file(genelist) from ch_genes_for_report_file
    file(gprofiler) from ch_gprofiler_for_report
    file(quote) from ch_quote_file

    output:
    file "*.zip"
    file "RNAseq_report.html" into rnaseq_report

    script:
    def genelistopt = genelist.name != 'NO_FILE' ? "--genelist $genelist" : ''
    def fastqcopt = fastqc.name != 'NO_FILE' ? "$fastqc" : ''
    def contrastsopt = contrasts.name != 'DEFAULT' ? "--contrasts $contrasts" : ''
    """
    unzip $deseq2 .
    unzip $multiqc .
    unzip $gprofiler .
    mkdir QC
    mv multiqc/multiqc_plots/ multiqc/multiqc_data/ multiqc/multiqc_report.html $fastqcopt QC/
    Execute_report.R --report '$baseDir/assets/RNAseq_report.Rmd' --output 'RNAseq_report.html' --proj_summary $proj_summary \
    --versions $softwareversions --model $model --config $config $contrastsopt $genelistopt --quote $quote
    mv qc_summary.tsv QC/
    zip -r report.zip RNAseq_report.html DESeq2/ QC/ gProfileR/ $quote
    """
}


/*
 * STEP 4 - Output Description HTML
 */
process output_documentation {
    publishDir "${params.outdir}/pipeline_info", mode: 'copy'

    input:
    file output_docs from ch_output_docs

    output:
    file "results_description.html"

    script:
    """
    markdown_to_html.r $output_docs results_description.html
    """
}



/*
 * Completion e-mail notification
 */
workflow.onComplete {

    // Set up the e-mail variables
    def subject = "[qbicsoftware/rnadeseq] Successful: $workflow.runName"
    if(!workflow.success){
      subject = "[qbicsoftware/rnadeseq] FAILED: $workflow.runName"
    }
    def email_fields = [:]
    email_fields['version'] = workflow.manifest.version
    email_fields['runName'] = custom_runName ?: workflow.runName
    email_fields['success'] = workflow.success
    email_fields['dateComplete'] = workflow.complete
    email_fields['duration'] = workflow.duration
    email_fields['exitStatus'] = workflow.exitStatus
    email_fields['errorMessage'] = (workflow.errorMessage ?: 'None')
    email_fields['errorReport'] = (workflow.errorReport ?: 'None')
    email_fields['commandLine'] = workflow.commandLine
    email_fields['projectDir'] = workflow.projectDir
    email_fields['summary'] = summary
    email_fields['summary']['Date Started'] = workflow.start
    email_fields['summary']['Date Completed'] = workflow.complete
    email_fields['summary']['Pipeline script file path'] = workflow.scriptFile
    email_fields['summary']['Pipeline script hash ID'] = workflow.scriptId
    if(workflow.repository) email_fields['summary']['Pipeline repository Git URL'] = workflow.repository
    if(workflow.commitId) email_fields['summary']['Pipeline repository Git Commit'] = workflow.commitId
    if(workflow.revision) email_fields['summary']['Pipeline Git branch/tag'] = workflow.revision
    if(workflow.container) email_fields['summary']['Docker image'] = workflow.container
    email_fields['summary']['Nextflow Version'] = workflow.nextflow.version
    email_fields['summary']['Nextflow Build'] = workflow.nextflow.build
    email_fields['summary']['Nextflow Compile Timestamp'] = workflow.nextflow.timestamp

    // On success try attach the RNAseq report ot the email
    def qbic_report = null
    try {
        if (workflow.success) {
            qbic_report = rnaseq_report.getVal()
            if (qbic_report.getClass() == ArrayList){
                log.warn "[qbicsoftware/rnadeseq] Found multiple reports from process 'RNAseq report', will use only one"
                qbic_report = qbic_report[0]
            }
        }
    } catch (all) {
        log.warn "[qbicsoftware/rnadeseq] Could not attach RNAseq report to summary email"
    }

    // Render the TXT template
    def engine = new groovy.text.GStringTemplateEngine()
    def tf = new File("$baseDir/assets/email_template.txt")
    def txt_template = engine.createTemplate(tf).make(email_fields)
    def email_txt = txt_template.toString()

    // Render the HTML template
    def hf = new File("$baseDir/assets/email_template.html")
    def html_template = engine.createTemplate(hf).make(email_fields)
    def email_html = html_template.toString()

    // Render the sendmail template
    def smail_fields = [ email: params.email, subject: subject, email_txt: email_txt, email_html: email_html, baseDir: "$baseDir", mqcFile: qbic_report, mqcMaxSize: params.maxMultiqcEmailFileSize.toBytes() ]
    def sf = new File("$baseDir/assets/sendmail_template.txt")
    def sendmail_template = engine.createTemplate(sf).make(smail_fields)
    def sendmail_html = sendmail_template.toString()

    // Send the HTML e-mail
    if (params.email) {
        try {
          if( params.plaintext_email ){ throw GroovyException('Send plaintext e-mail, not HTML') }
          // Try to send HTML e-mail using sendmail
          [ 'sendmail', '-t' ].execute() << sendmail_html
          log.info "[qbicsoftware/rnadeseq] Sent summary e-mail to $params.email (sendmail)"
        } catch (all) {
          // Catch failures and try with plaintext
          [ 'mail', '-s', subject, params.email ].execute() << email_txt
          log.info "[qbicsoftware/rnadeseq] Sent summary e-mail to $params.email (mail)"
        }
    }

    // Write summary e-mail HTML to a file
    def output_d = new File( "${params.outdir}/pipeline_info/" )
    if( !output_d.exists() ) {
      output_d.mkdirs()
    }
    def output_hf = new File( output_d, "pipeline_report.html" )
    output_hf.withWriter { w -> w << email_html }
    def output_tf = new File( output_d, "pipeline_report.txt" )
    output_tf.withWriter { w -> w << email_txt }

    c_reset = params.monochrome_logs ? '' : "\033[0m";
    c_purple = params.monochrome_logs ? '' : "\033[0;35m";
    c_green = params.monochrome_logs ? '' : "\033[0;32m";
    c_red = params.monochrome_logs ? '' : "\033[0;31m";

    if (workflow.stats.ignoredCountFmt > 0 && workflow.success) {
      log.info "${c_purple}Warning, pipeline completed, but with errored process(es) ${c_reset}"
      log.info "${c_red}Number of ignored errored process(es) : ${workflow.stats.ignoredCountFmt} ${c_reset}"
      log.info "${c_green}Number of successfully ran process(es) : ${workflow.stats.succeedCountFmt} ${c_reset}"
    }

    if(workflow.success){
        log.info "${c_purple}[qbicsoftware/rnadeseq]${c_green} Pipeline completed successfully${c_reset}"
    } else {
        checkHostname()
        log.info "${c_purple}[qbicsoftware/rnadeseq]${c_red} Pipeline completed with errors${c_reset}"
    }

}


def nfcoreHeader(){
    // Log colors ANSI codes
    c_reset = params.monochrome_logs ? '' : "\033[0m";
    c_dim = params.monochrome_logs ? '' : "\033[2m";
    c_black = params.monochrome_logs ? '' : "\033[0;30m";
    c_green = params.monochrome_logs ? '' : "\033[0;32m";
    c_yellow = params.monochrome_logs ? '' : "\033[0;33m";
    c_blue = params.monochrome_logs ? '' : "\033[0;34m";
    c_purple = params.monochrome_logs ? '' : "\033[0;35m";
    c_cyan = params.monochrome_logs ? '' : "\033[0;36m";
    c_white = params.monochrome_logs ? '' : "\033[0;37m";

    return """    ${c_dim}----------------------------------------------------${c_reset}
                                            ${c_green},--.${c_black}/${c_green},-.${c_reset}
    ${c_blue}        ___     __   __   __   ___     ${c_green}/,-._.--~\'${c_reset}
    ${c_blue}  |\\ | |__  __ /  ` /  \\ |__) |__         ${c_yellow}}  {${c_reset}
    ${c_blue}  | \\| |       \\__, \\__/ |  \\ |___     ${c_green}\\`-._,-`-,${c_reset}
                                            ${c_green}`._,._,\'${c_reset}
    ${c_purple}  qbicsoftware/rnadeseq v${workflow.manifest.version}${c_reset}
    ${c_dim}----------------------------------------------------${c_reset}
    """.stripIndent()
}

def checkHostname(){
    def c_reset = params.monochrome_logs ? '' : "\033[0m"
    def c_white = params.monochrome_logs ? '' : "\033[0;37m"
    def c_red = params.monochrome_logs ? '' : "\033[1;91m"
    def c_yellow_bold = params.monochrome_logs ? '' : "\033[1;93m"
    if(params.hostnames){
        def hostname = "hostname".execute().text.trim()
        params.hostnames.each { prof, hnames ->
            hnames.each { hname ->
                if(hostname.contains(hname) && !workflow.profile.contains(prof)){
                    log.error "====================================================\n" +
                            "  ${c_red}WARNING!${c_reset} You are running with `-profile $workflow.profile`\n" +
                            "  but your machine hostname is ${c_white}'$hostname'${c_reset}\n" +
                            "  ${c_yellow_bold}It's highly recommended that you use `-profile $prof${c_reset}`\n" +
                            "============================================================"
                }
            }
        }
    }
}

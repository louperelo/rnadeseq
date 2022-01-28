#!/usr/bin/env nextflow
/*
========================================================================================
    // TODO: Replace all nf-core with qbic-pipelines
    nf-core/rnadeseq
========================================================================================
    Github : https://github.com/qbic-pipelines/rnadeseq
----------------------------------------------------------------------------------------
*/

nextflow.enable.dsl = 2

/*
========================================================================================
    GENOME PARAMETER VALUES
========================================================================================
*/

/*
========================================================================================
    VALIDATE & PRINT PARAMETER SUMMARY
========================================================================================
*/
WorkflowMain.initialise(workflow, params, log)
/*
========================================================================================
    NAMED WORKFLOW FOR PIPELINE
========================================================================================
*/

include { RNADESEQ } from './workflows/rnadeseq'
//
// WORKFLOW: Run main qbic-pipelines/rnadeseq analysis pipeline
//
workflow QBIC_RNADESEQ {
    RNADESEQ ()
}
print "RNADESEQ"

/*
========================================================================================
    RUN ALL WORKFLOWS
========================================================================================
*/

//
// WORKFLOW: Execute a single named workflow for the pipeline
// See: https://github.com/nf-core/rnaseq/issues/619
//
workflow {
    QBIC_RNADESEQ ()
}

/*
========================================================================================
    THE END
========================================================================================
*/

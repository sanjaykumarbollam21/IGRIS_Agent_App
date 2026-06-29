const logger = require('../utils/logger');
const { WorkflowExecution } = require('../models');

/**
 * WorkflowEngine
 * Executes stateful, multi-step workflows (Sagas) with automatic compensation
 * (rollback) upon failure.
 */
class WorkflowEngine {
  constructor() {
    this.workflows = new Map();
  }

  register(workflow) {
    this.workflows.set(workflow.name, workflow);
    logger.info(`[WorkflowEngine] Registered workflow: ${workflow.name}`);
  }

  /**
   * Start a workflow execution
   */
  async start(workflowName, userId, initialContext = {}) {
    const workflow = this.workflows.get(workflowName);
    if (!workflow) throw new Error(`Workflow ${workflowName} not found`);

    const execution = await WorkflowExecution.create({
      userId,
      workflowName,
      status: 'RUNNING',
      contextData: initialContext
    });

    // Run async to not block the caller
    this._executeSteps(workflow, execution).catch(err => {
      logger.error(`[WorkflowEngine] Unhandled workflow error: ${err.message}`);
    });

    return execution.id;
  }

  async _executeSteps(workflow, execution) {
    const steps = workflow.getSteps();
    let currentContext = { ...execution.contextData };

    for (let i = execution.currentStep; i < steps.length; i++) {
      const step = steps[i];
      logger.info(`[WorkflowEngine:${workflow.name}] Executing step ${i}: ${step.name}`);

      try {
        currentContext = await step.execute(currentContext);
        
        await execution.update({
          currentStep: i + 1,
          contextData: currentContext
        });

      } catch (error) {
        logger.error(`[WorkflowEngine:${workflow.name}] Step ${i} failed: ${error.message}`);
        
        await execution.update({
          status: 'FAILED',
          errorData: error.message
        });

        // Trigger Compensation (Rollback)
        await this._compensate(workflow, execution, i, currentContext);
        return;
      }
    }

    await execution.update({ status: 'COMPLETED' });
    logger.info(`[WorkflowEngine:${workflow.name}] Workflow completed successfully`);
  }

  async _compensate(workflow, execution, failedStepIndex, context) {
    const steps = workflow.getSteps();
    logger.info(`[WorkflowEngine:${workflow.name}] Starting compensation...`);

    for (let i = failedStepIndex - 1; i >= 0; i--) {
      const step = steps[i];
      if (step.compensate) {
        try {
          logger.info(`[WorkflowEngine:${workflow.name}] Compensating step ${i}: ${step.name}`);
          await step.compensate(context);
        } catch (compError) {
          logger.error(`[WorkflowEngine:${workflow.name}] Compensation failed at step ${i}: ${compError.message}`);
          // In a real system, you might trigger human intervention here (Dead Letter Queue)
        }
      }
    }

    await execution.update({ status: 'COMPENSATED' });
    logger.info(`[WorkflowEngine:${workflow.name}] Compensation finished.`);
  }
}

module.exports = new WorkflowEngine();

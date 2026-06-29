/**
 * BaseWorkflow
 * Abstract class defining a multi-step Saga or Workflow.
 */
class BaseWorkflow {
  constructor(name) {
    this.name = name;
    this.steps = [];
  }

  /**
   * Register a step in the workflow
   * @param {Object} step 
   * @param {string} step.name
   * @param {Function} step.execute - async (context) => newContext
   * @param {Function} step.compensate - async (context) => void
   */
  addStep(step) {
    this.steps.push(step);
    return this;
  }

  getSteps() {
    return this.steps;
  }
}

module.exports = BaseWorkflow;

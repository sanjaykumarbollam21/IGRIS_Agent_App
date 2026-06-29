const { DynamicTool } = require('@langchain/core/tools');
const { z } = require('zod');

async function run() {
  const tool = new DynamicTool({
    name: 'web_search',
    description: 'search',
    schema: z.object({
      query: z.string()
    }),
    func: async (input) => {
      return 'done';
    }
  });

  console.log('--- _call implementation ---');
  console.log(tool._call.toString());

  console.log('--- call implementation ---');
  console.log(tool.call.toString());
}

run();

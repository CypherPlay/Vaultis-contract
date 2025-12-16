
const { docgen } = require('solidity-docgen');
const path = require('path');
const fs = require('fs');

async function generateDocs() {
  const config = {
    output: 'docs/',
    templates: './docgen-templates',
    exclude: [],
    pages: 'files',
    page_title: '{{contractName}} - Documentation',
    solc_version: '0.8.20',
    extra_pages: [],
    collapse_references: false,
    prettier: true,
    prettier_plugin: require.resolve('prettier-plugin-solidity'),
  };

  // Ensure the docs directory exists
  const docsDir = path.resolve(__dirname, '../docs');
  if (!fs.existsSync(docsDir)) {
    fs.mkdirSync(docsDir, { recursive: true });
  }

  await docgen(config);
  console.log('Documentation generated successfully in the docs/ directory.');
}

generateDocs().catch(console.error);

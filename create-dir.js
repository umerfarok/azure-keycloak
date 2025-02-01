const fs = require('fs').promises;
const path = require('path');

const dirStructure = {
  'README.md': null,
  'terraform': {
    'main.tf': null,
    'variables.tf': null,
    'outputs.tf': null,
    'providers.tf': null,
    'backend.tf': null,
    'terraform.tfvars.example': null
  },
  'kubernetes': {
    'nginx-ingress': {
      'values.yaml': null
    },
    'cert-manager': {
      'values.yaml': null,
      'cluster-issuer.yaml': null
    },
    'keycloak': {
      'values.yaml': null,
      'ingress.yaml': null
    }
  },
  'scripts': {
    'deploy.sh': null,
    'setup-terraform-state.sh': null,
    'cleanup.sh': null
  }
};

async function createDirectoryStructure(basePath, structure) {
  for (const [name, content] of Object.entries(structure)) {
    const fullPath = path.join(basePath, name);
    
    if (content === null) {
      // It's a file
      try {
        await fs.writeFile(fullPath, '');
        console.log(`Created file: ${fullPath}`);
      } catch (err) {
        console.error(`Error creating file ${fullPath}:`, err);
      }
    } else {
      // It's a directory
      try {
        await fs.mkdir(fullPath, { recursive: true });
        console.log(`Created directory: ${fullPath}`);
        await createDirectoryStructure(fullPath, content);
      } catch (err) {
        console.error(`Error creating directory ${fullPath}:`, err);
      }
    }
  }
}

async function main() {
  const basePath = path.resolve(__dirname);
  try {
    await createDirectoryStructure(basePath, dirStructure);
    console.log('Directory structure created successfully!');
  } catch (err) {
    console.error('Error creating directory structure:', err);
  }
}

main();
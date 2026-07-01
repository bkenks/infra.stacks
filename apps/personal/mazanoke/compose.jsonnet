// mazanoke — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// No secrets — no env_file needed.
{
  name: 'mazanoke',
  include: [
    { path: './compose.stack.yaml' },
  ],
}

// Parent compose (Komodo deploy entrypoint), renders to compose.yaml. No secrets for this stack.
{
  name: 'termix',
  include: [
    { path: './compose.stack.yaml' },
  ],
}

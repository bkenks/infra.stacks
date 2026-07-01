// frappe — parent compose (Komodo deploy entrypoint). Renders to compose.yaml.
// Interpolation env_file: /dev/shm/frappe.env (rendered by the Infisical agent;
// registry agentServices dest `frappe.env`, project `frappe`, folder `/frappe`).
{
  name: 'frappe',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/frappe.env'],
    },
  ],
}

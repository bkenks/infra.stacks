{
  name: 'frappe',
  include: [
    {
      path: './compose.stack.yaml',
      env_file: ['/dev/shm/frappe.env'],
    },
  ],
}

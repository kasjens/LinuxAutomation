# Ansible Test Project

A simple Ansible project to verify your installation is working correctly.

## Quick Test

Run the test playbook to verify Ansible is working:

```bash
cd ~/ansible-projects
ansible-playbook playbooks/hello-project.yml
```

## Expected Output

If everything is working, you should see:
- Ansible connects to localhost successfully
- A test file is created at `/tmp/my-ansible-project.txt`
- Success message displayed

## Verify the Test

Check that the test file was created:

```bash
cat /tmp/my-ansible-project.txt
```

You should see a message with the current date and hostname.

## Troubleshooting

If the test fails:

1. **Check Ansible installation:**
   ```bash
   ansible --version
   ```

2. **Test basic connectivity:**
   ```bash
   ansible local -m ping
   ```

3. **Check the log file:**
   ```bash
   tail /var/log/ansible/ansible.log
   ```

That's it! If the hello-project.yml playbook runs successfully, your Ansible setup is working correctly.

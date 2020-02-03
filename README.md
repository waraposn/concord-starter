# Concord Starter

This provides an initial setup for Concord that will allow you to learn, experiment, demo, and provision resources to public clouds from your local machine.

## Step 1: create a profile

`./00-concord-setup.sh`

This will create the necessary files to start with Concord in your `~/.concord` directory. You will likely want to edit the generated files to suit your needs before you initialize Concord in the next step.

## Step 2: Initialize Concord

`./01-concord-initialize.sh`

This will setup the Concord in its entirety on your local machine in one pass. This will also setup the necessary organization, project, and secrets required for the example projects. Everything generated here is based on the profile created above.

Once this is complete, you can take a look at the installation by logging into the console:

`./02-concord-console.sh` (The API key to login will be copied to the clipboard for you on a Mac)

`http://localhost:8080/#/login?useApiKey=true` (The API key for the demo setup is auBy4eDWrKWsyhiDp3AQiw)

In the Concord console you should be able to see your organization, project, and the secrets associated with that organization.

# Step 3: Run the demos!

During the setup, all the examples are parameterized so all you need to do to run a particular demo is go to that directory and `run.sh`. For example:

```
cd examples/01-docker
./run.sh
```

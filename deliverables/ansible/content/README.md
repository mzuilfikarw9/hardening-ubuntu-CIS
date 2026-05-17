# SCAP Security Guide datastreams

`openscap-scan.yml` expects two SSG 0.1.80 datastream files in this
directory before first run. They are not checked into git because of
size. The same version (0.1.80) matches the test run already done on
the Ubuntu 24 test VM, so results are directly comparable.

## Required files

```
content/
  ssg-ubuntu2204-ds.xml   # used for Ubuntu 22.04 hosts
  ssg-ubuntu2404-ds.xml   # used for Ubuntu 24.04 hosts
```

## One-time setup (on the Ansible control node)

```bash
cd deliverables/ansible/content

VERSION=0.1.80
BASE=https://github.com/ComplianceAsCode/content/releases/download/v${VERSION}

curl -LO ${BASE}/scap-security-guide-${VERSION}.zip
unzip -j scap-security-guide-${VERSION}.zip \
  "scap-security-guide-${VERSION}/ssg-ubuntu2204-ds.xml" \
  "scap-security-guide-${VERSION}/ssg-ubuntu2404-ds.xml"
rm scap-security-guide-${VERSION}.zip

# Verify
ls -l ssg-ubuntu2204-ds.xml ssg-ubuntu2404-ds.xml
```

Both files should be ~30-40 MB. If `unzip` can't find the paths above
(directory name inside the zip can vary by release), run
`unzip -l scap-security-guide-${VERSION}.zip | grep ds.xml` to find
the exact paths and adjust.

## Upgrading the SSG version later

Change `ssg_version` at the top of `openscap-scan.yml` and re-download
into this directory. The playbook reads datastreams by name, not by
version, so both old and new can coexist during a transition.

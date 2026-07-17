# Contributing to Open Telecom Lab

Thank you for your interest in contributing! This project follows professional open-source practices to maintain quality and consistency.

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How to Contribute](#how-to-contribute)
- [Development Workflow](#development-workflow)
- [Branch Naming](#branch-naming)
- [Commit Messages](#commit-messages)
- [Pull Request Process](#pull-request-process)
- [Documentation Standards](#documentation-standards)

---

## Code of Conduct

This project adheres to the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

---

## How to Contribute

### 🐛 Reporting Bugs

1. Check existing [issues](../../issues) to avoid duplicates.
2. Use the **Bug Report** issue template.
3. Include: OS version, Open5GS version, UERANSIM version, logs, and PCAP files if applicable.

### 💡 Suggesting Features

1. Use the **Feature Request** issue template.
2. Describe the use case and how it aligns with the project roadmap.

### 🔬 Adding Lab Exercises

1. Use the **Lab Exercise** issue template.
2. Include prerequisites, objectives, and expected outcomes.

### 📝 Improving Documentation

- Fix typos, improve explanations, or add protocol walkthroughs.
- Ensure Mermaid diagrams render correctly.
- Add Wireshark filter references where applicable.

---

## Development Workflow

```
main ← release/vX.Y ← develop ← feature/your-feature
```

1. **Fork** the repository.
2. **Create a branch** from `develop` (see naming conventions below).
3. **Make changes** with clear, atomic commits.
4. **Test** your changes locally.
5. **Submit a PR** to `develop` using the PR template.

---

## Branch Naming

| Pattern | Use Case | Example |
|---------|----------|---------|
| `feature/<name>` | New functionality | `feature/ims-setup` |
| `docs/<name>` | Documentation only | `docs/ngap-walkthrough` |
| `fix/<name>` | Bug fixes | `fix/pfcp-timeout` |
| `lab/<name>` | New lab exercise | `lab/05-volte-call` |
| `config/<name>` | Configuration changes | `config/multi-slice` |

---

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <subject>

[optional body]

[optional footer]
```

### Types

| Type | Description |
|------|-------------|
| `feat` | New feature or lab |
| `fix` | Bug fix |
| `docs` | Documentation changes |
| `config` | Configuration updates |
| `refactor` | Code/structure refactoring |
| `test` | Adding or updating tests |
| `chore` | Maintenance tasks |

### Examples

```
feat(lab): add PDU session establishment lab
docs(protocols): add NGAP message flow walkthrough
fix(config): correct AMF PLMN ID mismatch
config(open5gs): update SMF PFCP client address
```

---

## Pull Request Process

1. **Fill out** the PR template completely.
2. **Link** related issues using `Closes #123` or `Relates to #456`.
3. **Ensure** all documentation is properly formatted.
4. **Include** PCAP files or log excerpts for protocol-related changes.
5. **Request review** from at least one maintainer.

### PR Checklist

- [ ] Branch follows naming conventions
- [ ] Commits follow Conventional Commits format
- [ ] Documentation is updated
- [ ] Mermaid diagrams render correctly
- [ ] No sensitive data (real IMSI, keys) is exposed
- [ ] Changes tested on Ubuntu 22.04+ with Open5GS

---

## Documentation Standards

- Use **Mermaid** for architecture and flow diagrams.
- Use **fenced code blocks** with language identifiers.
- Reference **3GPP specifications** (e.g., TS 23.501) where applicable.
- Keep line lengths reasonable (< 120 characters in prose).
- Use **admonitions** for warnings and important notes:
  ```markdown
  > **⚠️ Warning:** This will disrupt active PDU sessions.
  ```

---

## 📬 Questions?

Open a [Discussion](../../discussions) or reach out via issues. We're happy to help!

# CI/CD Email Notification Setup

This guide explains how to configure email notifications for CI/CD pipeline failures in storage-sage (government security software).

---

## Overview

The CI pipeline automatically sends email notifications when builds fail on the `main` branch. This ensures immediate awareness of security or quality issues.

**Notification Triggers:**
- ✅ Validation failures (fmt, vet, govulncheck, gitleaks)
- ✅ Lint failures (golangci-lint, gosec)
- ✅ Test failures (unit tests, coverage threshold)
- ✅ Build failures (compilation errors)
- ✅ Docker build failures

---

## Required GitHub Secrets

Configure the following secrets in your GitHub repository settings:

**Path**: `Settings → Secrets and variables → Actions → Repository secrets`

### 1. MAIL_SERVER
SMTP server address for sending emails.

**Examples:**
- Gmail: `smtp.gmail.com`
- Office 365: `smtp.office365.com`
- AWS SES: `email-smtp.us-east-1.amazonaws.com`
- SendGrid: `smtp.sendgrid.net`
- Mailgun: `smtp.mailgun.org`

```
Name: MAIL_SERVER
Value: smtp.gmail.com
```

### 2. MAIL_PORT (Optional)
SMTP server port. Defaults to `587` if not specified.

**Common Ports:**
- `587` - STARTTLS (recommended)
- `465` - SSL/TLS
- `25` - Unencrypted (not recommended)

```
Name: MAIL_PORT
Value: 587
```

### 3. MAIL_USERNAME
Username for SMTP authentication.

**Examples:**
- Gmail: `your-email@gmail.com`
- Office 365: `your-email@company.com`
- AWS SES: `AKIAIOSFODNN7EXAMPLE` (Access Key ID)
- SendGrid: `apikey` (literal string)
- Mailgun: `postmaster@mg.yourdomain.com`

```
Name: MAIL_USERNAME
Value: ci-notifications@yourorg.gov
```

### 4. MAIL_PASSWORD
Password or app-specific password for SMTP authentication.

**Examples:**
- Gmail: App-specific password (16 characters, requires 2FA enabled)
- Office 365: Account password or app password
- AWS SES: Secret Access Key
- SendGrid: API Key
- Mailgun: Domain SMTP password

**Security Note**: Use app-specific passwords when available, never your main account password.

```
Name: MAIL_PASSWORD
Value: abcd efgh ijkl mnop  (Gmail app password example)
```

### 5. MAIL_TO
Email address(es) to receive notifications. For multiple recipients, separate with commas.

```
Name: MAIL_TO
Value: security-team@yourorg.gov,devops@yourorg.gov
```

### 6. MAIL_FROM (Optional)
Sender email address. Defaults to `MAIL_USERNAME` if not specified.

```
Name: MAIL_FROM
Value: storage-sage-ci@yourorg.gov
```

---

## Provider-Specific Setup

### Gmail (Free)

1. **Enable 2-Factor Authentication**:
   - Go to: https://myaccount.google.com/security
   - Enable 2-Step Verification

2. **Create App Password**:
   - Go to: https://myaccount.google.com/apppasswords
   - Select app: "Mail"
   - Select device: "Other (Custom name)" → Enter "StorageSage CI"
   - Click "Generate"
   - Copy the 16-character password

3. **Configure Secrets**:
   ```
   MAIL_SERVER: smtp.gmail.com
   MAIL_PORT: 587
   MAIL_USERNAME: your-email@gmail.com
   MAIL_PASSWORD: abcd efgh ijkl mnop  (app password)
   MAIL_TO: recipient@example.com
   ```

**Limitations**:
- 500 emails/day limit
- Not suitable for production government systems
- Use only for personal/test environments

---

### Office 365 / Microsoft 365 (Government Compatible)

1. **Enable SMTP AUTH**:
   - Admin center → Settings → Org settings → Mail → Modern authentication
   - Enable "Authenticated SMTP" (SMTP AUTH)

2. **Create Dedicated Account** (Recommended):
   - Create service account: `storage-sage-ci@yourorg.onmicrosoft.com`
   - Assign appropriate licenses
   - Set strong password

3. **Configure Secrets**:
   ```
   MAIL_SERVER: smtp.office365.com
   MAIL_PORT: 587
   MAIL_USERNAME: storage-sage-ci@yourorg.onmicrosoft.com
   MAIL_PASSWORD: [service account password]
   MAIL_TO: security-team@yourorg.onmicrosoft.com
   ```

**Government Compliance**:
- ✅ FedRAMP Moderate authorized
- ✅ FISMA compliant
- ✅ Supports encryption in transit
- ✅ Audit logging available

---

### AWS SES (Government Compatible)

**Prerequisites**: AWS account with SES configured

1. **Verify Email Domain**:
   - SES Console → Verified identities → Verify a domain
   - Add DNS records (TXT, CNAME, MX)

2. **Create SMTP Credentials**:
   - SES Console → Account dashboard → SMTP settings
   - Click "Create SMTP credentials"
   - Save Access Key ID and Secret Access Key

3. **Move out of Sandbox** (Required for production):
   - SES Console → Account dashboard → Request production access
   - Complete form with use case details

4. **Configure Secrets**:
   ```
   MAIL_SERVER: email-smtp.us-east-1.amazonaws.com
   MAIL_PORT: 587
   MAIL_USERNAME: AKIAIOSFODNN7EXAMPLE  (SMTP Access Key ID)
   MAIL_PASSWORD: [SMTP Secret Access Key]
   MAIL_FROM: ci-notifications@yourdomain.gov
   MAIL_TO: security-team@yourdomain.gov
   ```

**Government Compliance**:
- ✅ FedRAMP High authorized (GovCloud)
- ✅ FISMA High compliant
- ✅ Supports FIPS 140-2
- ✅ Comprehensive audit logging (CloudTrail)

**Cost**: ~$0.10 per 1,000 emails

---

### SendGrid (Commercial)

1. **Create API Key**:
   - SendGrid Dashboard → Settings → API Keys
   - Click "Create API Key"
   - Name: "StorageSage CI"
   - Permissions: "Mail Send" (Full Access)
   - Copy API key (starts with `SG.`)

2. **Verify Sender**:
   - Settings → Sender Authentication
   - Verify single sender OR domain

3. **Configure Secrets**:
   ```
   MAIL_SERVER: smtp.sendgrid.net
   MAIL_PORT: 587
   MAIL_USERNAME: apikey  (literal string "apikey")
   MAIL_PASSWORD: SG.xxxxxxxxxxxxxxxxxxxxxxxxxx  (API key)
   MAIL_FROM: ci-notifications@yourdomain.com
   MAIL_TO: team@yourdomain.com
   ```

**Cost**: Free tier (100 emails/day), then $15-20/month

---

### Mailgun (Commercial)

1. **Add Domain**:
   - Mailgun Dashboard → Sending → Domains → Add New Domain
   - Configure DNS records

2. **Get SMTP Credentials**:
   - Dashboard → Sending → Domain settings
   - SMTP credentials section
   - Copy login and password

3. **Configure Secrets**:
   ```
   MAIL_SERVER: smtp.mailgun.org
   MAIL_PORT: 587
   MAIL_USERNAME: postmaster@mg.yourdomain.com
   MAIL_PASSWORD: [SMTP password from dashboard]
   MAIL_FROM: ci@yourdomain.com
   MAIL_TO: team@yourdomain.com
   ```

**Cost**: Free tier (5,000 emails/month), then pay-as-you-go

---

## Testing Email Configuration

### 1. Manual Test (GitHub Actions)

1. Make a commit that will fail linting:
   ```bash
   echo "package main; func test(){" > test.go
   git add test.go
   git commit -m "test: trigger CI failure for email notification"
   git push origin main
   ```

2. Wait for CI to fail
3. Check your inbox for notification email

### 2. Verify Secrets Are Set

Check that all required secrets are configured:

```bash
# This will list secret names (not values)
gh secret list
```

Expected output:
```
MAIL_SERVER
MAIL_PORT
MAIL_USERNAME
MAIL_PASSWORD
MAIL_TO
MAIL_FROM
```

---

## Troubleshooting

### Emails Not Received

**Check 1**: Verify secrets are set correctly
```bash
gh secret list
```

**Check 2**: Review GitHub Actions logs
- Go to: Actions tab → Failed workflow run
- Check "Notify on Failure" job logs
- Look for SMTP connection errors

**Check 3**: Check spam/junk folder

**Check 4**: Verify SMTP credentials
- Test SMTP connection manually:
```bash
telnet smtp.gmail.com 587
EHLO localhost
QUIT
```

### Common Errors

#### "Authentication failed"
- **Cause**: Wrong username/password
- **Fix**: Regenerate app password, update `MAIL_PASSWORD` secret

#### "Connection refused"
- **Cause**: Wrong SMTP server or port
- **Fix**: Verify `MAIL_SERVER` and `MAIL_PORT` values

#### "Recipient address rejected"
- **Cause**: Email address not verified or domain not authenticated
- **Fix**: Verify sender domain in your email provider

#### "Daily sending quota exceeded"
- **Cause**: Gmail free tier limit (500/day)
- **Fix**: Upgrade to Google Workspace or use AWS SES

---

## Email Notification Format

When CI fails, you'll receive an email with:

**Subject**: `🚨 CI FAILED: storage-sage main branch`

**Body**:
```
CI Pipeline Failed for storage-sage (Government Security Software)

Repository: ChrisB0-2/storage-sage
Branch: main
Commit: a1b2c3d4
Author: ChrisB0-2
Workflow: CI
Run: https://github.com/ChrisB0-2/storage-sage/actions/runs/123456789

Please investigate immediately.

---
This is an automated security notification for government software compliance.
```

---

## Security Considerations

### Secrets Management Best Practices

1. **Use Dedicated Service Account**:
   - Don't use personal email accounts
   - Create `ci-notifications@yourorg.gov` or similar

2. **Minimal Permissions**:
   - Grant only "Send Email" permission
   - No read/delete mailbox access needed

3. **Rotate Credentials**:
   - Rotate SMTP passwords every 90 days
   - Use calendar reminders for rotation

4. **Monitor Usage**:
   - Review SMTP logs monthly
   - Alert on unusual sending patterns

5. **Audit Access**:
   - Limit who can view/edit GitHub secrets
   - Log all secret modifications

### Government Compliance

For government deployments:

- ✅ **Use FedRAMP-authorized providers** (AWS SES, Office 365 GovCloud)
- ✅ **Enable encryption in transit** (TLS 1.2+)
- ✅ **Audit logging** (CloudTrail for AWS SES, audit logs for O365)
- ✅ **Data residency** (use GovCloud regions if required)
- ❌ **Avoid consumer services** (Gmail, Yahoo, free tiers)

---

## Advanced Configuration

### Multiple Notification Channels

To send to multiple recipients:

```
MAIL_TO: team1@org.gov,team2@org.gov,security@org.gov
```

### Custom Email Templates

The email body can be customized in `.github/workflows/ci.yml`:

```yaml
- name: Send email notification
  uses: dawidd6/action-send-mail@v3
  with:
    # ... other settings ...
    body: |
      [CRITICAL] CI Pipeline Failure

      Your custom message here.

      Repository: ${{ github.repository }}
      Run URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
```

### Conditional Notifications

Currently sends only on `main` branch failures. To change:

```yaml
# Notify on all branches
if: failure() && github.event_name == 'push'

# Notify on specific branch patterns
if: failure() && startsWith(github.ref, 'refs/heads/release/')
```

---

## Cost Analysis

| Provider | Free Tier | Paid Tier | Government Compliant |
|----------|-----------|-----------|---------------------|
| Gmail | 500/day | N/A | ❌ No |
| Office 365 | Requires license | $5-20/user/month | ✅ Yes (FedRAMP) |
| AWS SES | None | $0.10/1000 emails | ✅ Yes (FedRAMP High) |
| SendGrid | 100/day | $15-20/month | ⚠️ No (commercial) |
| Mailgun | 5000/month | Pay as you go | ⚠️ No (commercial) |

**Recommendation for Government**: **AWS SES (GovCloud)** or **Office 365 GCC High**

---

## Support

If you encounter issues:

1. Review GitHub Actions logs
2. Test SMTP connection manually
3. Check provider's status page
4. Consult provider documentation:
   - [Gmail SMTP](https://support.google.com/mail/answer/7126229)
   - [Office 365 SMTP](https://learn.microsoft.com/en-us/exchange/mail-flow-best-practices/how-to-set-up-a-multifunction-device-or-application-to-send-email-using-microsoft-365-or-office-365)
   - [AWS SES](https://docs.aws.amazon.com/ses/latest/dg/smtp-credentials.html)

---

**Last Updated**: 2025-12-15
**Version**: 1.1.0

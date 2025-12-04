#!/bin/bash
#
# Generate StorageSage Compliance Report
# Runs verification tests and generates formatted report
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_SCRIPT="${SCRIPT_DIR}/verify_daemon_compliance.sh"
REPORT_DIR="${REPORT_DIR:-./reports}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="${REPORT_DIR}/compliance_report_${TIMESTAMP}.md"

# Create report directory
mkdir -p "${REPORT_DIR}"

echo "=========================================="
echo "StorageSage Compliance Report Generator"
echo "=========================================="
echo ""

# Run compliance tests
echo "Running compliance tests..."
if "${TEST_SCRIPT}" 2>&1 | tee "${REPORT_DIR}/test_output_${TIMESTAMP}.log"; then
    TEST_EXIT_CODE=0
else
    TEST_EXIT_CODE=$?
fi

# Extract test results from log
TEST_LOG="${REPORT_DIR}/test_output_${TIMESTAMP}.log"

# Generate markdown report
cat > "${REPORT_FILE}" <<EOF
# StorageSage Daemon Compliance Report

**Generated:** $(date)
**Test Script:** verify_daemon_compliance.sh
**Test Log:** test_output_${TIMESTAMP}.log

## Executive Summary

This report documents the compliance of the StorageSage daemon with its specification.

## Test Results

EOF

# Extract test results
if [ -f "${TEST_LOG}" ]; then
    echo "## Detailed Test Results" >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"
    echo '```' >> "${REPORT_FILE}"
    cat "${TEST_LOG}" >> "${REPORT_FILE}"
    echo '```' >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"
fi

# Extract summary
if grep -q "Test Summary:" "${TEST_LOG}" 2>/dev/null; then
    echo "## Summary" >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"
    grep -A 10 "Test Summary:" "${TEST_LOG}" >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"
fi

# Extract overall compliance
if grep -q "OVERALL:" "${TEST_LOG}" 2>/dev/null; then
    echo "## Overall Compliance" >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"
    grep "OVERALL:" "${TEST_LOG}" >> "${REPORT_FILE}"
    echo "" >> "${REPORT_FILE}"
fi

# Add specification reference
cat >> "${REPORT_FILE}" <<EOF

## Specification Reference

See STORAGE_SAGE_SPECIFICATION.md for complete specification details.

## Test Evidence

All test evidence is available in:
- Test Log: \`test_output_${TIMESTAMP}.log\`
- Test Directory: Check test script output for test directory location

## Recommendations

1. Review any failed tests and address issues
2. Review partial test results and verify expected behavior
3. Run tests regularly to ensure continued compliance
4. Update specification if behavior changes

## Next Steps

1. Address any failed tests
2. Verify partial test results
3. Update documentation if needed
4. Re-run tests after fixes

---

**Report Generated:** $(date)
**Report File:** ${REPORT_FILE}
EOF

echo ""
echo "=========================================="
echo "Compliance Report Generated"
echo "=========================================="
echo "Report: ${REPORT_FILE}"
echo "Test Log: ${REPORT_DIR}/test_output_${TIMESTAMP}.log"
echo ""
echo "View report with:"
echo "  cat ${REPORT_FILE}"
echo ""

exit ${TEST_EXIT_CODE}


const EMPLOYEE_LOGIN_DOMAIN = "sherize.app";

function employeeIdCandidates(value) {
    const compact = String(value || "").trim().toUpperCase().replace(/[^A-Z0-9]/g, "");
    const match = compact.match(/^SHR(\d{4}|\d{6})$/);
    if (!match) return [];

    const digits = match[1];
    return digits.length === 4
        ? [`SHR-${digits}`, `SHR${digits}`]
        : [`SHR${digits}`, `SHR-${digits}`];
}

function idToEmail(employeeId) {
    const local = String(employeeId).trim().toLowerCase().replace(/[^a-z0-9._-]/g, "");
    return `${local}@${EMPLOYEE_LOGIN_DOMAIN}`;
}

async function generateUniqueEmployeeId(db) {
    for (let attempt = 0; attempt < 100; attempt++) {
        const employeeId = `SHR-${1000 + Math.floor(Math.random() * 9000)}`;
        const candidates = employeeIdCandidates(employeeId);
        let isDuplicate = false;
        for (const field of ["employeeId", "workerId"]) {
            for (const candidate of candidates) {
                const duplicate = await db.collection("users")
                    .where(field, "==", candidate)
                    .limit(1)
                    .get();
                if (!duplicate.empty) {
                    isDuplicate = true;
                    break;
                }
            }
            if (isDuplicate) break;
        }
        if (!isDuplicate) return employeeId;
    }
    return null;
}

module.exports = {
    EMPLOYEE_LOGIN_DOMAIN,
    employeeIdCandidates,
    generateUniqueEmployeeId,
    idToEmail,
};
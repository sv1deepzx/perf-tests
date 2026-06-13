import http from 'k6/http';
import { check } from 'k6';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.0.2/index.js';

const TARGET_URL = __ENV.TARGET_URL || 'http://app-mvc:8080';
const ENDPOINT   = __ENV.ENDPOINT   || '/api/cpu';
const OUTPUT_FILE = __ENV.OUTPUT_FILE || '/results/output.json';

export const options = {
  summaryTrendStats: ['med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  stages: [
    { duration: '20s', target: 200 },
    { duration: '60s', target: 200 },
    { duration: '10s', target: 0 },
  ],
};

export default function () {
  const res = http.get(`${TARGET_URL}${ENDPOINT}`, { timeout: '30s' });
  check(res, { 'status 200': (r) => r.status === 200 });
}

export function handleSummary(data) {
  return {
    [OUTPUT_FILE]: JSON.stringify(data, null, 2),
    stdout: textSummary(data, { indent: ' ', enableColors: true }),
  };
}

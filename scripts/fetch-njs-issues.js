// Fetch open issues from nginx/njs and synthesize into /tmp/njs-issues.md
// Usage: bun run scripts/fetch-njs-issues.js [issue-number]

const REPO = "nginx/njs";
const OUT = "/tmp/njs-issues.md";
const BASE = "https://api.github.com";
const issueNumber = process.argv[2] ? Number(process.argv[2]) : null;

async function fetchIssues() {
  if (issueNumber) {
    const url = `${BASE}/repos/${REPO}/issues/${issueNumber}`;
    console.log(`Fetching issue #${issueNumber} from ${REPO}...`);

    const res = await fetch(url, {
      headers: {
        Accept: "application/vnd.github.v3+json",
        "User-Agent": "nginz-njs-scripts",
      },
    });

    if (!res.ok) {
      throw new Error(`GitHub API returned ${res.status}: ${await res.text()}`);
    }

    const issue = await res.json();

    // Single-issue endpoint returns a PR if the number corresponds to one
    if (issue.pull_request) {
      throw new Error(`#${issueNumber} is a pull request, not an issue`);
    }

    return [issue];
  }

  const url = `${BASE}/repos/${REPO}/issues?state=open&per_page=100&sort=created&direction=asc`;
  console.log(`Fetching open issues from ${REPO}...`);

  const res = await fetch(url, {
    headers: {
      Accept: "application/vnd.github.v3+json",
      "User-Agent": "nginz-njs-scripts",
    },
  });

  if (!res.ok) {
    throw new Error(`GitHub API returned ${res.status}: ${await res.text()}`);
  }

  const data = await res.json();

  // Exclude pull requests (they also appear in /issues endpoint)
  const issues = data.filter((i) => !i.pull_request);
  console.log(`  total raw: ${data.length}, filtered (no PRs): ${issues.length}`);

  return issues;
}

async function fetchComments(issues) {
  // Fetch comments for each issue with comments > 0
  const results = await Promise.all(
    issues.map(async (issue) => {
      if (issue.comments === 0) return { ...issue, commentList: [] };
      const url = `${BASE}/repos/${REPO}/issues/${issue.number}/comments?per_page=50`;
      const res = await fetch(url, {
        headers: {
          Accept: "application/vnd.github.v3+json",
          "User-Agent": "nginz-njs-scripts",
        },
      });
      if (!res.ok) {
        console.warn(`  warn: failed to fetch comments for #${issue.number}`);
        return { ...issue, commentList: [] };
      }
      const comments = await res.json();
      return { ...issue, commentList: comments };
    }),
  );
  return results;
}

function formatDate(iso) {
  return iso?.slice(0, 10) ?? "unknown";
}

function formatLabels(labels) {
  return labels.length === 0 ? "none" : labels.map((l) => l.name).join(", ");
}

function blockquote(text) {
  if (!text) return "> *(no description)*";
  return text
    .split("\n")
    .map((line) => `> ${line}`)
    .join("\n");
}

function synthesizeIssues(issues) {
  const lines = [];

  if (issueNumber) {
    lines.push(`# nginx/njs Issue #${issueNumber}`);
  } else {
    lines.push("# Open Issues from nginx/njs");
    lines.push("");
    lines.push(`**Total open issues:** ${issues.length}`);
  }
  lines.push(`**Fetched:** ${new Date().toISOString().slice(0, 10)}`);
  lines.push("");

  for (const issue of issues) {
    const num = issue.number;
    const title = issue.title;
    const url = issue.html_url;
    const created = formatDate(issue.created_at);
    const updated = formatDate(issue.updated_at);
    const labels = formatLabels(issue.labels);
    const commentCount = issue.comments;
    const body = issue.body ?? "";

    lines.push(`## [#${num}](${url}) — ${title}`);
    lines.push("");
    lines.push(`- **Created:** ${created} | **Updated:** ${updated}`);
    lines.push(`- **Comments:** ${commentCount} | **Labels:** ${labels}`);
    lines.push("");
    lines.push("### Description");
    lines.push("");
    lines.push(blockquote(body.trim() || null));
    lines.push("");

    // Comments
    const commentList = issue.commentList ?? [];
    if (commentList.length > 0) {
      lines.push(`### Recent Comments (${commentList.length})`);
      lines.push("");
      for (const c of commentList) {
        const author = c.user?.login ?? "unknown";
        const date = formatDate(c.created_at);
        const text = (c.body ?? "").trim();
        lines.push(`**${author}** (${date}):`);
        lines.push("");
        lines.push(blockquote(text || null));
        lines.push("");
        lines.push("---");
        lines.push("");
      }
    }

    lines.push("---");
    lines.push("");
  }

  return lines.join("\n");
}

async function main() {
  const issues = await fetchIssues();
  const withComments = await fetchComments(issues);
  const md = synthesizeIssues(withComments);
  await Bun.write(OUT, md);
  console.log(`Wrote ${issues.length} issues to ${OUT}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

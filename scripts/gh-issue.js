// Fetch a specific issue or PR from nginx/njs or nginx/nginx and synthesize into /tmp/{repo}-{id}.md
// Usage: bun run gh-issue -- <njs|nginx> <issue|pr> <number>

const REPOS = {
  njs: "nginx/njs",
  nginx: "nginx/nginx",
};

const BASE = "https://api.github.com";

const repoArg = process.argv[2];
const typeArg = process.argv[3];
const numberArg = Number(process.argv[4]);
const OUT = `/tmp/${repoArg}-${numberArg}.md`;

const REPO = REPOS[repoArg];
if (!REPO) {
  console.error(`Usage: bun run gh-issue -- <njs|nginx> <issue|pr> <number>`);
  console.error(`  first arg must be "njs" or "nginx", got: ${repoArg ?? "(none)"}`);
  process.exit(1);
}

if (typeArg !== "issue" && typeArg !== "pr") {
  console.error(`Usage: bun run gh-issue -- <njs|nginx> <issue|pr> <number>`);
  console.error(`  second arg must be "issue" or "pr", got: ${typeArg ?? "(none)"}`);
  process.exit(1);
}

if (!numberArg || Number.isNaN(numberArg)) {
  console.error(`Usage: bun run gh-issue -- <njs|nginx> <issue|pr> <number>`);
  console.error(`  third arg must be a number, got: ${process.argv[4] ?? "(none)"}`);
  process.exit(1);
}

const typeLabel = typeArg === "pr" ? "PR" : "Issue";

async function fetchItem() {
  // PRs use /pulls/{n}, issues use /issues/{n}. Comments for both live under /issues/{n}/comments.
  const path = typeArg === "pr" ? "pulls" : "issues";
  const url = `${BASE}/repos/${REPO}/${path}/${numberArg}`;
  console.log(`Fetching ${typeLabel.toLowerCase()} #${numberArg} from ${REPO}...`);

  const res = await fetch(url, {
    headers: {
      Accept: "application/vnd.github.v3+json",
      "User-Agent": "nginz-njs-scripts",
    },
  });

  if (!res.ok) {
    throw new Error(`GitHub API returned ${res.status}: ${await res.text()}`);
  }

  return res.json();
}

async function fetchComments(item) {
  // Both issues and PRs share the same comments endpoint
  const commentCount = item.comments ?? item.review_comments ?? 0;
  if (!commentCount) return { ...item, commentList: [] };

  const url = `${BASE}/repos/${REPO}/issues/${item.number}/comments?per_page=50`;
  const res = await fetch(url, {
    headers: {
      Accept: "application/vnd.github.v3+json",
      "User-Agent": "nginz-njs-scripts",
    },
  });

  if (!res.ok) {
    console.warn(`  warn: failed to fetch comments for #${item.number}`);
    return { ...item, commentList: [] };
  }

  const comments = await res.json();
  return { ...item, commentList: comments };
}

function formatDate(iso) {
  return iso?.slice(0, 10) ?? "unknown";
}

function formatLabels(labels) {
  if (!labels || labels.length === 0) return "none";
  return labels.map((l) => l.name).join(", ");
}

function blockquote(text) {
  if (!text) return "> *(no description)*";
  return text
    .split("\n")
    .map((line) => `> ${line}`)
    .join("\n");
}

function synthesize(item) {
  const lines = [];
  const num = item.number;
  const title = item.title;
  const state = item.state;
  const url = item.html_url;
  const created = formatDate(item.created_at);
  const updated = formatDate(item.updated_at);
  const labels = formatLabels(item.labels);
  const comments = item.comments ?? 0;
  const body = item.body ?? "";

  lines.push(`# ${REPO} ${typeLabel} #${num} (${state})`);
  lines.push("");
  lines.push(`**Fetched:** ${new Date().toISOString().slice(0, 10)}`);
  lines.push("");

  lines.push(`## [#${num}](${url}) — ${title}`);
  lines.push("");
  lines.push(`- **State:** ${state} | **Created:** ${created} | **Updated:** ${updated}`);
  lines.push(`- **Comments:** ${comments} | **Labels:** ${labels}`);
  lines.push("");
  lines.push("### Description");
  lines.push("");
  lines.push(blockquote(body.trim() || null));
  lines.push("");

  // Comments
  const commentList = item.commentList ?? [];
  if (commentList.length > 0) {
    lines.push(`### Comments (${commentList.length})`);
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

  return lines.join("\n");
}

async function main() {
  const item = await fetchItem();
  const withComments = await fetchComments(item);
  const md = synthesize(withComments);
  await Bun.write(OUT, md);
  console.log(`Wrote to ${OUT}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

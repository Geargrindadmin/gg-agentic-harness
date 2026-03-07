#!/usr/bin/env node
/**
 * gg-skills-mcp-server
 * Exposes GGV3's 113 skills + 31 workflows as callable MCP tools.
 * Also provides dynamic tool creation (inspired by ai-meta-mcp-server):
 *   define_tool, call_tool, list_dynamic_tools, delete_tool
 *
 * Transport: stdio (compatible with .mcp.json Claude Code config)
 * Protocol:  Model Context Protocol v1 (@modelcontextprotocol/sdk)
 */
import * as fs from 'fs';
import * as path from 'path';
import * as url from 'url';

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  type Tool,
} from '@modelcontextprotocol/sdk/types.js';

import { SkillSearch } from './SkillSearch.js';
import { type SkillEntry, SkillsLoader } from './SkillsLoader.js';
import { ToolRegistry } from './ToolRegistry.js';
import { type WorkflowEntry, WorkflowLoader } from './WorkflowLoader.js';

// ── Resolve directories ────────────────────────────────────────────────────

const __dirname = path.dirname(url.fileURLToPath(import.meta.url));
const PROJECT_ROOT = path.resolve(__dirname, '../../..'); // mcp-servers/gg-skills/dist → project root

const SKILLS_DIR = process.env['SKILLS_DIR'] ?? path.join(PROJECT_ROOT, '.agent', 'skills');
const WORKFLOWS_DIR =
  process.env['WORKFLOWS_DIR'] ?? path.join(PROJECT_ROOT, '.agent', 'workflows');

// ── Load catalog ───────────────────────────────────────────────────────────

const skillsLoader = new SkillsLoader(SKILLS_DIR);
const workflowLoader = new WorkflowLoader(WORKFLOWS_DIR);

// Dynamic tool registry (persisted between server restarts)
const TOOLS_DB_PATH =
  process.env['TOOLS_DB_PATH'] ??
  path.join(PROJECT_ROOT, 'mcp-servers', 'gg-skills', 'dynamic-tools.json');
const toolRegistry = new ToolRegistry(TOOLS_DB_PATH);

let skills: SkillEntry[] = [];
let workflows: WorkflowEntry[] = [];
let search: SkillSearch;

function loadCatalog(): void {
  skills = skillsLoader.load();
  workflows = workflowLoader.load();
  search = new SkillSearch(skills, workflows);
  process.stderr.write(
    `[gg-skills] Loaded ${skills.length} skills, ${workflows.length} workflows\n`
  );

  // Write catalog snapshot to disk for /agentic-status
  const catalogPath = path.join(__dirname, '..', 'skills-catalog.json');
  fs.writeFileSync(
    catalogPath,
    JSON.stringify(
      {
        generated: new Date().toISOString(),
        skillCount: skills.length,
        workflowCount: workflows.length,
        skills: skills.map((s) => ({
          slug: s.slug,
          name: s.name,
          category: s.category,
          description: s.description.slice(0, 120),
        })),
        workflows: workflows.map((w) => ({
          slug: w.slug,
          description: w.description.slice(0, 120),
        })),
      },
      null,
      2
    )
  );
}

loadCatalog();

// ── MCP Tool definitions ───────────────────────────────────────────────────

const tools: Tool[] = [
  {
    name: 'list_skills',
    description:
      'List all available GGV3 skills with their names, categories, and descriptions. Use this to discover which skills exist before calling use_skill().',
    inputSchema: {
      type: 'object' as const,
      properties: {
        category: {
          type: 'string',
          description:
            'Optional: filter by category (Core, Frontend, Backend, Security, Testing, Advertising, DevOps, Evaluation, Evaluate-Loop, Mobile, Documents, OSS Tooling)',
        },
      },
    },
  },
  {
    name: 'use_skill',
    description:
      'Load and apply a specific GGV3 skill by its slug name. Returns the full SKILL.md content including principles, patterns, and guidelines. Apply the returned knowledge to the current task.',
    inputSchema: {
      type: 'object' as const,
      properties: {
        name: {
          type: 'string',
          description:
            'The skill slug (e.g. "api-patterns", "clean-code", "vulnerability-scanner"). Use list_skills() to find valid names.',
        },
      },
      required: ['name'],
    },
  },
  {
    name: 'find_skills',
    description:
      'Search for relevant skills using natural language. Returns the top 5 most relevant skills for the given query. Use this when you know what you need but not which skill name to use.',
    inputSchema: {
      type: 'object' as const,
      properties: {
        query: {
          type: 'string',
          description:
            'Natural language query, e.g. "stripe payment integration", "react performance", "SQL injection", "auth debugging"',
        },
        limit: {
          type: 'number',
          description: 'Max results to return (default: 5)',
        },
      },
      required: ['query'],
    },
  },
  {
    name: 'list_workflows',
    description:
      'List all available GGV3 slash command workflows (e.g. /board-meeting, /minion, /go). Returns workflow names and descriptions.',
    inputSchema: {
      type: 'object' as const,
      properties: {},
    },
  },
  {
    name: 'use_workflow',
    description:
      'Load a specific GGV3 workflow by name. Returns the full workflow markdown including step-by-step instructions. Use for slash commands like /board-meeting, /minion, /go.',
    inputSchema: {
      type: 'object' as const,
      properties: {
        name: {
          type: 'string',
          description:
            'Workflow slug (e.g. "board-meeting", "minion", "go", "write-plan"). Use list_workflows() to find valid names.',
        },
      },
      required: ['name'],
    },
  },
  {
    name: 'reload_catalog',
    description:
      'Hot-reload the skills and workflows catalog from disk. Use after adding new skills or workflows without restarting the server.',
    inputSchema: {
      type: 'object' as const,
      properties: {},
    },
  },
  // ── Dynamic tool creation (inspired by ai-meta-mcp-server) ───────────────
  {
    name: 'define_tool',
    description: [
      'Create a new custom tool at runtime. The tool is persisted to disk and immediately available via call_tool().',
      'Runtime options: "javascript" (sandboxed vm.Script, 10s timeout) or "shell" (requires ALLOW_SHELL_EXECUTION=true).',
      'JavaScript implementation receives an `args` object matching the inputSchema properties.',
      'Use console.log() to produce output. Return value is also captured.',
      'Example: define a "format_bytes" tool that converts bytes to human-readable strings.',
    ].join(' '),
    inputSchema: {
      type: 'object' as const,
      properties: {
        name: { type: 'string', description: 'Unique tool name (snake_case, e.g. "format_bytes")' },
        description: {
          type: 'string',
          description: 'What this tool does — used by agents to discover and select it',
        },
        runtime: {
          type: 'string',
          enum: ['javascript', 'shell'],
          description: 'Execution runtime. Default: javascript',
        },
        implementation: {
          type: 'string',
          description:
            'JS function body (has access to `args` object) or shell script (args available as TOOL_ARG_<KEY> env vars)',
        },
        inputSchema: {
          type: 'object',
          description: 'JSON Schema properties for the tool inputs (object with property keys)',
        },
        createdBy: {
          type: 'string',
          description: 'Optional: agent ID for traceability (e.g. "builder-bd-42")',
        },
      },
      required: ['name', 'description', 'implementation'],
    },
  },
  {
    name: 'call_tool',
    description:
      "Execute a previously defined dynamic tool by name. Pass args matching the tool's inputSchema.",
    inputSchema: {
      type: 'object' as const,
      properties: {
        name: {
          type: 'string',
          description: 'Name of the dynamic tool to call (from list_dynamic_tools or define_tool)',
        },
        args: {
          type: 'object',
          description: "Arguments to pass to the tool — must match the tool's inputSchema",
        },
      },
      required: ['name'],
    },
  },
  {
    name: 'list_dynamic_tools',
    description:
      'List all custom tools created at runtime via define_tool(). Returns names, descriptions, runtimes, and creation dates.',
    inputSchema: { type: 'object' as const, properties: {} },
  },
  {
    name: 'delete_tool',
    description: 'Permanently delete a custom tool from the registry. This cannot be undone.',
    inputSchema: {
      type: 'object' as const,
      properties: {
        name: { type: 'string', description: 'Name of the dynamic tool to delete' },
      },
      required: ['name'],
    },
  },
];

// ── Server setup ───────────────────────────────────────────────────────────

const server = new Server(
  { name: 'gg-skills-mcp-server', version: '1.0.0' },
  { capabilities: { tools: {} } }
);

// List tools handler
server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools }));

type ToolCallArgs = Record<string, unknown>;
type ToolResult = { content: { type: 'text'; text: string }[]; isError?: boolean };

// eslint-disable-next-line complexity
function handleDynamicTool(name: string, args: ToolCallArgs): ToolResult | null {
  switch (name) {
    case 'define_tool': {
      const {
        name: toolName,
        description: toolDesc,
        runtime = 'javascript',
        implementation,
        inputSchema: schema = {},
        createdBy,
      } = args as {
        name: string;
        description: string;
        runtime?: 'javascript' | 'shell';
        implementation: string;
        inputSchema?: Record<string, unknown>;
        createdBy?: string;
      };
      if (!/^[a-z][a-z0-9_]*$/.test(toolName)) {
        return {
          content: [
            { type: 'text', text: 'Tool name must be snake_case (lowercase, underscores only)' },
          ],
          isError: true,
        };
      }
      if (runtime === 'shell' && process.env['ALLOW_SHELL_EXECUTION'] !== 'true') {
        return {
          content: [
            {
              type: 'text',
              text: 'Shell runtime disabled. Set ALLOW_SHELL_EXECUTION=true to enable.',
            },
          ],
          isError: true,
        };
      }
      toolRegistry.define({
        name: toolName,
        description: toolDesc,
        runtime,
        implementation,
        inputSchema: schema,
        createdAt: new Date().toISOString(),
        createdBy,
      });
      process.stderr.write(`[gg-skills] Dynamic tool defined: ${toolName} (${runtime})\n`);
      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify(
              {
                status: 'defined',
                name: toolName,
                runtime,
                usage: `call_tool("${toolName}", { ...args })`,
              },
              null,
              2
            ),
          },
        ],
      };
    }
    case 'call_tool': {
      const { name: toolName, args: toolArgs = {} } = args as {
        name: string;
        args?: Record<string, unknown>;
      };
      if (!toolRegistry.get(toolName)) {
        return {
          content: [
            {
              type: 'text',
              text: `Dynamic tool "${toolName}" not found. Call list_dynamic_tools() to see available tools.`,
            },
          ],
          isError: true,
        };
      }
      const result = toolRegistry.execute(toolName, toolArgs);
      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify(
              {
                tool: toolName,
                exitCode: result.exitCode,
                durationMs: result.durationMs,
                output: result.output,
              },
              null,
              2
            ),
          },
        ],
        ...(result.exitCode !== 0 ? { isError: true as const } : {}),
      };
    }
    case 'list_dynamic_tools': {
      const dTools = toolRegistry.list();
      const text =
        dTools.length === 0
          ? 'No dynamic tools defined yet. Call define_tool() to create one.'
          : JSON.stringify(
              {
                total: dTools.length,
                tools: dTools.map((t) => ({
                  name: t.name,
                  description: t.description.slice(0, 100),
                  runtime: t.runtime,
                  createdAt: t.createdAt,
                  createdBy: t.createdBy,
                })),
                usage: 'Call call_tool(name, args) to execute any tool',
              },
              null,
              2
            );
      return { content: [{ type: 'text', text }] };
    }
    case 'delete_tool': {
      const { name: toolName } = args as { name: string };
      const deleted = toolRegistry.delete(toolName);
      return {
        content: [
          {
            type: 'text',
            text: deleted ? `Tool "${toolName}" deleted.` : `Tool "${toolName}" not found.`,
          },
        ],
        ...(deleted ? {} : { isError: true as const }),
      };
    }
    default:
      return null;
  }
}

// Call tool handler
// eslint-disable-next-line max-lines-per-function, complexity
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args = {} } = request.params;

  try {
    switch (name) {
      case 'list_skills': {
        const categoryFilter = (args as { category?: string }).category?.toLowerCase();
        const filtered = categoryFilter
          ? skills.filter((s) => s.category.toLowerCase() === categoryFilter)
          : skills;

        const grouped = filtered.reduce<Record<string, { slug: string; description: string }[]>>(
          (acc, s) => {
            if (!acc[s.category]) acc[s.category] = [];
            acc[s.category]!.push({ slug: s.slug, description: s.description.slice(0, 100) });
            return acc;
          },
          {}
        );

        return {
          content: [
            {
              type: 'text' as const,
              text: JSON.stringify(
                {
                  total: filtered.length,
                  categories: grouped,
                  usage: 'Call use_skill(name) with any slug to load the full skill',
                },
                null,
                2
              ),
            },
          ],
        };
      }

      case 'use_skill': {
        const skillName = (args as { name: string }).name;
        const content = skillsLoader.loadContent(skillName);
        if (!content) {
          return {
            content: [
              {
                type: 'text' as const,
                text: `Skill "${skillName}" not found. Call list_skills() to see valid skill names.`,
              },
            ],
            isError: true,
          };
        }
        return {
          content: [
            {
              type: 'text' as const,
              text: `# Skill: ${skillName}\n\n${content}`,
            },
          ],
        };
      }

      case 'find_skills': {
        const { query, limit } = args as { query: string; limit?: number };
        const results = search.findSkills(query, limit ?? 5);
        if (results.length === 0) {
          return {
            content: [
              {
                type: 'text' as const,
                text: `No skills found for "${query}". Try list_skills() to browse all available skills.`,
              },
            ],
          };
        }
        return {
          content: [
            {
              type: 'text' as const,
              text: JSON.stringify(
                {
                  query,
                  results: results.map((s) => ({
                    slug: s.slug,
                    category: s.category,
                    description: s.description.slice(0, 150),
                    triggers: s.triggers.slice(0, 5),
                  })),
                  usage: 'Call use_skill(slug) to load any of these',
                },
                null,
                2
              ),
            },
          ],
        };
      }

      case 'list_workflows': {
        return {
          content: [
            {
              type: 'text' as const,
              text: JSON.stringify(
                {
                  total: workflows.length,
                  workflows: workflows.map((w) => ({
                    name: w.slug,
                    description: w.description.slice(0, 120),
                  })),
                  usage: 'Call use_workflow(name) to load any workflow',
                },
                null,
                2
              ),
            },
          ],
        };
      }

      case 'use_workflow': {
        const workflowName = (args as { name: string }).name;
        const content = workflowLoader.loadContent(workflowName);
        if (!content) {
          return {
            content: [
              {
                type: 'text' as const,
                text: `Workflow "${workflowName}" not found. Call list_workflows() to see valid workflow names.`,
              },
            ],
            isError: true,
          };
        }
        return {
          content: [
            {
              type: 'text' as const,
              text: `# Workflow: /${workflowName}\n\n${content}`,
            },
          ],
        };
      }

      case 'reload_catalog': {
        loadCatalog();
        return {
          content: [
            {
              type: 'text' as const,
              text: `Catalog reloaded: ${skills.length} skills, ${workflows.length} workflows`,
            },
          ],
        };
      }

      default: {
        // Delegate to dynamic tool handler first
        const dynResult = handleDynamicTool(name, args);
        if (dynResult) return dynResult;
        return {
          content: [{ type: 'text' as const, text: `Unknown tool: ${name}` }],
          isError: true,
        };
      }
    }
  } catch (err) {
    return {
      content: [
        {
          type: 'text' as const,
          text: `Error: ${err instanceof Error ? err.message : String(err)}`,
        },
      ],
      isError: true,
    };
  }
});

// ── CLI convenience: --list flag ───────────────────────────────────────────
if (process.argv.includes('--list')) {
  process.stdout.write(`Skills (${skills.length}):\n`);
  skills.forEach((s) => process.stdout.write(`  ${s.slug.padEnd(40)} [${s.category}]\n`));
  process.stdout.write(`\nWorkflows (${workflows.length}):\n`);
  workflows.forEach((w) => process.stdout.write(`  /${w.slug}\n`));
  process.exit(0);
}

// ── Start server ───────────────────────────────────────────────────────────
const transport = new StdioServerTransport();
await server.connect(transport);
process.stderr.write('[gg-skills] MCP server running on stdio\n');

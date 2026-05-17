const MAX_MANUAL_SKILLS = 10;
const MAX_SKILL_NAME_LENGTH = 200;

/**
 * Parse @agent and /skill directives from query text.
 * @param {string} query
 * @param {{ agents?: Array<{ id: string, name: string }>, skills?: Array<{ name: string }> }} catalogs
 */
function parseQueryDirectives(query, catalogs = {}) {
  const agents = catalogs.agents ?? [];
  const skills = catalogs.skills ?? [];
  let cleanQuery = query;
  let agentId = null;
  const manualSkills = [];

  const agentByName = new Map();
  const agentById = new Map();
  for (const agent of agents) {
    if (agent.name) {
      agentByName.set(agent.name.toLowerCase(), agent.id);
    }
    if (agent.id) {
      agentById.set(agent.id, agent.id);
    }
  }

  const skillNames = new Set(skills.map((s) => s.name).filter(Boolean));
  const hasSkillCatalog = skillNames.size > 0;

  const agentMatch = cleanQuery.match(/@([A-Za-z0-9_.-]+)/);
  if (agentMatch) {
    const token = agentMatch[1];
    const resolved = agentById.get(token) ?? agentByName.get(token.toLowerCase());
    if (resolved) {
      agentId = resolved;
    }
    cleanQuery = cleanQuery.replace(agentMatch[0], '').trim();
  }

  const skillPattern = /\/([A-Za-z0-9_.-]+)/g;
  let skillMatch;
  const skillMatches = [];
  while ((skillMatch = skillPattern.exec(cleanQuery)) !== null) {
    skillMatches.push(skillMatch);
  }
  for (const match of skillMatches) {
    const name = match[1];
    if (name.length > MAX_SKILL_NAME_LENGTH) {
      continue;
    }
    if (hasSkillCatalog && !skillNames.has(name)) {
      continue;
    }
    if (!manualSkills.includes(name)) {
      manualSkills.push(name);
    }
    cleanQuery = cleanQuery.replace(match[0], '').trim();
  }
  cleanQuery = cleanQuery.replace(/\s+/g, ' ').trim();

  return {
    cleanQuery: cleanQuery || query.trim(),
    agentId,
    manualSkills: manualSkills.slice(0, MAX_MANUAL_SKILLS),
  };
}

module.exports = {
  parseQueryDirectives,
};

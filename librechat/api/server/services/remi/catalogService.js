const { ResourceType, PermissionBits } = require('librechat-data-provider');
const {
  findAccessibleResources,
  findPubliclyAccessibleResources,
} = require('~/server/services/PermissionService');
const db = require('~/models');

async function listAgentsForUser(req, limit = 50) {
  const userId = req.user?.id;
  const role = req.user?.role;
  if (!userId) {
    return [];
  }

  const accessibleIds = await findAccessibleResources({
    userId,
    role,
    resourceType: ResourceType.AGENT,
    requiredPermissions: PermissionBits.VIEW,
  });

  if (!accessibleIds?.length) {
    return [];
  }

  const data = await db.getListAgentsByAccess({
    accessibleIds,
    otherParams: {},
    limit,
    after: null,
  });
  const agents = data?.data ?? [];
  return agents
    .map((agent) => ({
      id: agent.id,
      name: agent.name || agent.id,
      description: agent.description || null,
    }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

async function listSkillsForUser(req, limit = 100) {
  const userId = req.user?.id;
  const role = req.user?.role;
  if (!userId) {
    return [];
  }

  const [accessibleIds, publicIds] = await Promise.all([
    findAccessibleResources({
      userId,
      role,
      resourceType: ResourceType.SKILL,
      requiredPermissions: PermissionBits.VIEW,
    }),
    findPubliclyAccessibleResources({
      resourceType: ResourceType.SKILL,
      requiredPermissions: PermissionBits.VIEW,
    }),
  ]);

  const mergedIds = Array.from(
    new Map([...accessibleIds, ...publicIds].map((id) => [id.toString(), id])).values(),
  );

  if (mergedIds.length === 0) {
    return [];
  }

  const result = await db.listSkillsByAccess({
    accessibleIds: mergedIds,
    limit,
  });

  const skills = Array.isArray(result?.skills) ? result.skills : [];
  return skills
    .filter((skill) => skill.userInvocable !== false)
    .map((skill) => ({
      name: skill.name,
      displayName: skill.displayTitle || skill.displayName || skill.name,
      description: skill.description || null,
    }))
    .filter((s) => s.name)
    .sort((a, b) => a.name.localeCompare(b.name));
}

async function getRemiCatalog(req) {
  const [agents, skills] = await Promise.all([
    listAgentsForUser(req, 50),
    listSkillsForUser(req, 100),
  ]);
  return { agents, skills };
}

async function resolveDefaultAgentId(req) {
  if (process.env.REMI_DEFAULT_AGENT_ID) {
    const agents = await listAgentsForUser(req, 200);
    const match = agents.find((a) => a.id === process.env.REMI_DEFAULT_AGENT_ID);
    if (match) {
      return match.id;
    }
  }
  const agents = await listAgentsForUser(req, 1);
  return agents[0]?.id ?? null;
}

module.exports = {
  getRemiCatalog,
  listAgentsForUser,
  listSkillsForUser,
  resolveDefaultAgentId,
};

import path from 'node:path';
import { pathToFileURL } from 'node:url';

export interface FreeModelEntry {
  id: string;
  label: string;
  tier: string;
  sweScore: string;
  context: string;
}

export interface FreeModelProviderCatalog {
  key: string;
  name: string;
  signupUrl: string;
  modelCount: number;
  tiers: string[];
  models: FreeModelEntry[];
}

export interface FreeModelsCatalogSnapshot {
  providers: FreeModelProviderCatalog[];
  totalProviders: number;
  totalModels: number;
}

async function loadSources(projectRoot: string): Promise<Record<string, { name: string; url: string; models: Array<[string, string, string, string, string]> }>> {
  const vendorFile = path.join(projectRoot, 'third-party', 'free-coding-models', 'sources.js');
  const module = await import(pathToFileURL(vendorFile).href);
  return module.sources as Record<string, { name: string; url: string; models: Array<[string, string, string, string, string]> }>;
}

export async function collectFreeModelsCatalog(projectRoot: string): Promise<FreeModelsCatalogSnapshot> {
  const sources = await loadSources(projectRoot);

  const providers = Object.entries(sources)
    .map(([key, source]) => {
      const models = (source.models || []).map((entry) => ({
        id: entry[0],
        label: entry[1],
        tier: entry[2],
        sweScore: entry[3],
        context: entry[4]
      }));
      const tiers = Array.from(new Set(models.map((entry) => entry.tier))).sort();
      return {
        key,
        name: source.name,
        signupUrl: source.url,
        modelCount: models.length,
        tiers,
        models
      };
    })
    .sort((left, right) => right.modelCount - left.modelCount || left.name.localeCompare(right.name));

  return {
    providers,
    totalProviders: providers.length,
    totalModels: providers.reduce((sum, provider) => sum + provider.modelCount, 0)
  };
}

export async function collectFreeModelProviders(projectRoot: string): Promise<Array<Pick<FreeModelProviderCatalog, 'key' | 'name' | 'signupUrl' | 'modelCount' | 'tiers'>>> {
  const snapshot = await collectFreeModelsCatalog(projectRoot);
  return snapshot.providers.map((provider) => ({
    key: provider.key,
    name: provider.name,
    signupUrl: provider.signupUrl,
    modelCount: provider.modelCount,
    tiers: provider.tiers
  }));
}

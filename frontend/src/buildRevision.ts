declare const __BRASSTUNE_BUILD_REVISION__: string;

export const buildRevision = __BRASSTUNE_BUILD_REVISION__;
export const buildRevisionMetaName = 'brasstune-build-revision';

export function exposeBuildRevision(documentRoot: Document) {
  let marker = documentRoot.head.querySelector<HTMLMetaElement>(
    `meta[name="${buildRevisionMetaName}"]`,
  );
  if (!marker) {
    marker = documentRoot.createElement('meta');
    marker.name = buildRevisionMetaName;
    documentRoot.head.append(marker);
  }
  marker.content = buildRevision;
}

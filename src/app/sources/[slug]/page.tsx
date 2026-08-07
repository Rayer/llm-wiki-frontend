"use client";

import { use } from "react";
import { DetailClient } from "@/components/DetailClient";
import { useT } from "@/lib/i18n";
import { getSource } from "@/lib/api";

export default function SourceDetailPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { t } = useT();
  const { slug } = use(params);

  return (
    <DetailClient
      slug={slug}
      label={t('Source.singular')}
      backHref="/sources"
      load={getSource}
      entryType="source"
    />
  );
}

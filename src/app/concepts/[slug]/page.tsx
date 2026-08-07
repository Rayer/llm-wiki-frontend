"use client";

import { use } from "react";
import { DetailClient } from "@/components/DetailClient";
import { useT } from "@/lib/i18n";
import { getConcept } from "@/lib/api";

export default function ConceptDetailPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { t } = useT();
  const { slug } = use(params);

  return (
    <DetailClient
      slug={slug}
      label={t('Entry.singular')}
      backHref="/concepts"
      load={getConcept}
      entryType="concept"
    />
  );
}

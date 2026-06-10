"use client";
import { useRouter } from "next/navigation";
import Thread from "../../components/Thread";
import useNavigation from "../../store/zustand";
import { BucketConfig, Screen } from "../../types/data";
import { useBucketConfigs } from "../../hooks/buckets/useBucketConfigs";
import { useCallback, useMemo } from "react";
import { buildThreadSteps } from "../../lib/helpers";

const HomeApp = () => {
  const router = useRouter();

  const navigation = useNavigation((state) => state.navigation);
  const setNavigation = useNavigation((state) => state.setNavigation);
  const { data } = useBucketConfigs();

  const bc = useMemo(
    () =>
      navigation.bucketId
        ? data?.find(
            (b: BucketConfig) =>
              String(b.bucket_id) === String(navigation.bucketId),
          )
        : undefined,
    [data, navigation.bucketId],
  );

  const steps = useMemo(
    () => buildThreadSteps(navigation, bc),
    [navigation, bc],
  );

  const jump = useCallback(
    (to: Screen | null) => {
      if (!to) return;

      const actions: Partial<Record<Screen, () => void>> = {
        year: () => {
          setNavigation({ screen: "year" });
          router.push("/");
        },
        month: () => {
          if (!navigation.year) return;
          setNavigation({ screen: "month", year: navigation.year });
          router.push(`/month/${navigation.year}`);
        },
        buckets: () => {
          if (!navigation.year || !navigation.monthId) return;
          setNavigation({
            screen: "buckets",
            year: navigation.year,
            monthId: navigation.monthId,
          });
          router.push(`/month/${navigation.monthId}`);
        },
      };

      actions[to]?.();
    },
    [navigation, router, setNavigation],
  );

  return <Thread steps={steps} onJump={jump} />;
};

export default HomeApp;

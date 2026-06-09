// lib/server-config.ts — server only, never import in client components
import { headers } from "next/headers";
import { dead_user_id } from "../utils/constants";
import { IS_PROD } from "./config";

export const head_user_id = async () => {
  const headerList = await headers();
  return IS_PROD ? headerList.get("x-user-id") : dead_user_id;
};

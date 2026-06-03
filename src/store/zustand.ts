import { create } from "zustand";
import { NavState } from "../types/data";
import { persist } from "zustand/middleware";
type NavigationStoreState = {
  navigation: NavState;
};

type NavigationStoreActions = {
  setNavigation: (nextNavigation: NavigationStoreState["navigation"]) => void;
};

type NavigationStore = NavigationStoreState & NavigationStoreActions;

const useNavigationStore = create<NavigationStore>()(
  persist(
    (set) => ({
      navigation: { screen: "year" },
      setNavigation: (nextNavigation) => {
        set({ navigation: nextNavigation });
      },
    }),
    {
      name: "navigation-storage", // localStorage key
    },
  ),
);

export default useNavigationStore;

import clsx from "clsx";
import React from "react";

type ButtonVariant =
  | "ghost"
  | "solid"
  | "yellow"
  | "outline"
  | "blue"
  | "danger";
type ButtonSize = "sm" | "md" | "lg";

type NavButtonProps = React.ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: ButtonVariant;
  size?: ButtonSize;
};

const variantClasses: Record<ButtonVariant, string> = {
  ghost: "btn-ghost",
  yellow: "btn-yellow",
  solid: "btn-w",
  outline: "",
  blue: "btn-blue",
  danger: "btn-danger",
};

const sizeClasses: Record<ButtonSize, string> = {
  sm: "btn-sm",
  md: "",
  lg: "btn-lg",
};

const NavButton = ({
  variant = "ghost",
  size = "sm",
  disabled,
  className,
  children,
  ...rest
}: NavButtonProps) => {
  const isGhost = disabled || variant === "ghost";
  const buttonClass = clsx(
    "btn",
    variantClasses[variant],
    sizeClasses[size],
    isGhost && "opacity-50 pointer-events-none",
    className,
  );

  return (
    <button className={buttonClass} disabled={isGhost} {...rest}>
      {children}
    </button>
  );
};

export default NavButton;

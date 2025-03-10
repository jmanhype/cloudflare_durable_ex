defmodule Mix.Tasks.ReleaseHex do
  @moduledoc """
  A mix task to help with releasing new versions to Hex.pm.

  This task:

  1. Updates version in mix.exs
  2. Updates CHANGELOG.md with the release date
  3. Commits these changes
  4. Creates a git tag
  5. Pushes changes and tags to GitHub
  6. Publishes the package to Hex.pm

  ## Examples

      mix release_hex 0.3.0
  """

  use Mix.Task
  import Mix.Shell.IO, only: [info: 1, error: 1, yes?: 1]

  @shortdoc "Releases a new version to Hex.pm"

  @impl true
  def run([version]) do
    # Validate version format
    unless version =~ ~r/^\d+\.\d+\.\d+$/ do
      error("Invalid version format: #{version}. Expected format: 0.1.0")
      exit({:shutdown, 1})
    end

    # Check for uncommitted changes
    if has_uncommitted_changes?() do
      error("There are uncommitted changes in the repository. Please commit or stash them before proceeding.")
      exit({:shutdown, 1})
    end

    # Check if we're on the main branch
    current_branch = get_current_branch()
    unless current_branch == "main" do
      unless yes?("You are not on the main branch (currently on #{current_branch}). Continue anyway?") do
        exit({:shutdown, 1})
      end
    end

    info("Preparing release #{version}...")

    # Update version in mix.exs
    update_mix_version(version)
    info("Updated version in mix.exs")

    # Update CHANGELOG.md with the release date
    update_changelog(version)
    info("Updated CHANGELOG.md")

    # Run formatter
    Mix.Task.run("format")
    info("Formatted code")

    # Run tests
    info("Running tests...")
    unless Mix.Task.run("test") == :ok do
      error("Tests failed. Aborting release.")
      exit({:shutdown, 1})
    end
    info("Tests passed")

    # Commit changes
    git_commit("Release v#{version}")
    info("Committed changes")

    # Create tag
    git_tag("v#{version}", "Release v#{version}")
    info("Created tag v#{version}")

    # Ask to push
    if yes?("Push changes and tag to GitHub?") do
      git_push()
      git_push_tags()
      info("Pushed changes and tags to GitHub")
    end

    # Ask to publish to Hex
    if yes?("Publish to Hex.pm?") do
      Mix.Task.run("hex.publish")
      info("Published to Hex.pm")
    end

    info("Release v#{version} completed!")
  end

  def run(_) do
    error("Usage: mix release_hex VERSION")
    error("Example: mix release_hex 0.3.0")
    exit({:shutdown, 1})
  end

  # Helper functions

  defp has_uncommitted_changes? do
    System.cmd("git", ["status", "--porcelain"]) |> elem(0) |> String.trim() |> String.length() > 0
  end

  defp get_current_branch do
    {branch, 0} = System.cmd("git", ["rev-parse", "--abbrev-ref", "HEAD"])
    String.trim(branch)
  end

  defp update_mix_version(version) do
    mix_file = Path.join(File.cwd!(), "mix.exs")
    content = File.read!(mix_file)
    updated_content = Regex.replace(~r/@version "[\d\.]+"/m, content, "@version \"#{version}\"")
    File.write!(mix_file, updated_content)
  end

  defp update_changelog(version) do
    changelog_file = Path.join(File.cwd!(), "CHANGELOG.md")
    content = File.read!(changelog_file)
    today = Date.utc_today() |> Date.to_string()
    updated_content = Regex.replace(
      ~r/## \[#{version}\](.*?)(\d{4}-\d{2}-\d{2})?/m,
      content,
      "## [#{version}]\\1#{today}"
    )
    File.write!(changelog_file, updated_content)
  end

  defp git_commit(message) do
    System.cmd("git", ["add", "mix.exs", "CHANGELOG.md"])
    System.cmd("git", ["commit", "-m", message])
  end

  defp git_tag(tag, message) do
    System.cmd("git", ["tag", "-a", tag, "-m", message])
  end

  defp git_push do
    System.cmd("git", ["push", "origin", get_current_branch()])
  end

  defp git_push_tags do
    System.cmd("git", ["push", "origin", "--tags"])
  end
end 
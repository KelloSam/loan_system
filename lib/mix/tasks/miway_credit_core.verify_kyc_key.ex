defmodule Mix.Tasks.MiwayCreditCore.VerifyKycKey do
  @moduledoc """
  Read-only sanity check: attempts to decrypt a sample of real stored
  KYC documents using the currently configured KYC_ENCRYPTION_KEY.
  Never prints the key or any decrypted content — only pass/fail
  counts and failing document ids. Safe to run in prod.

  This checks the key the *running app* already has loaded — it is
  not a disaster-recovery test of a *vaulted* copy of the key. See the
  deployment runbook §10 for that separate, human-gated exercise.

      mix miway_credit_core.verify_kyc_key
      mix miway_credit_core.verify_kyc_key --sample=20
  """

  use Mix.Task
  import Ecto.Query

  alias MiwayCreditCore.Customers
  alias MiwayCreditCore.Customers.KycDocument
  alias MiwayCreditCore.Repo

  @shortdoc "Sanity-checks the currently configured KYC encryption key"
  @default_sample_size 10

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} = OptionParser.parse(args, strict: [sample: :integer])
    sample_size = Keyword.get(opts, :sample, @default_sample_size)

    documents =
      KycDocument
      |> where([d], d.status != "purged")
      |> order_by(desc: :inserted_at)
      |> limit(^sample_size)
      |> Repo.all()

    case documents do
      [] ->
        Mix.shell().info("No KYC documents found to check.")

      documents ->
        {ok, failed} = check_documents(documents)
        Mix.shell().info("#{length(ok)}/#{length(documents)} decrypted successfully.")

        if failed != [] do
          Mix.shell().error("Failed to decrypt: #{Enum.map_join(failed, ", ", & &1.id)}")
          System.halt(1)
        end
    end
  end

  defp check_documents(documents) do
    Enum.split_with(documents, fn document ->
      try do
        is_binary(Customers.kyc_document_bytes(document))
      rescue
        _ -> false
      end
    end)
  end
end

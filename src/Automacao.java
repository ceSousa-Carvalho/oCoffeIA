import java.util.Scanner;

public class Automacao {
    public double somar(double valor1, double valor2) {
        return valor1 + valor2;
    }

    public double calcularMedia(double valor1, double valor2) {
        return (valor1 + valor2) / 2;
    }

    public boolean estaAprovado(double nota1, double nota2, double notaMinima) {
        return calcularMedia(nota1, nota2) >= notaMinima;
    }

    public void executar() {
        Scanner teclado = new Scanner(System.in);

        System.out.println("=== Automação de Notas ===");
        System.out.print("Digite a primeira nota: ");
        double nota1 = teclado.nextDouble();

        System.out.print("Digite a segunda nota: ");
        double nota2 = teclado.nextDouble();

        double soma = somar(nota1, nota2);
        double media = calcularMedia(nota1, nota2);
        boolean aprovado = estaAprovado(nota1, nota2, 7.0);

        System.out.println("\nResultado:");
        System.out.println("Soma: " + soma);
        System.out.println("Média: " + media);
        System.out.println("Status: " + (aprovado ? "Aprovado" : "Reprovado"));

        teclado.close();
    }
}

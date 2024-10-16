#include "data_export.cuh"
#include "Dirichlet_bcs.cuh"
#include "linear_solver.cuh"
#include "mesh_2d.cuh"
#include "numerical_integrator_2d.cuh"
#include "sparse_matrix.cuh"

#include "common/gpu_timer.cuh"

#include <vector>

int main(int argc, char *argv[]){
	GpuTimer timer;
    
    timer.start();

    Mesh2D mesh;
    if(!mesh.loadMeshFromFile("../data/TestProblem2.dat"))
        return EXIT_FAILURE;

    timer.stop("Mesh import");

    const int problemSize = mesh.getVertices().size;

    DirichletBCs bcs;
    
    timer.start();

    {
        std::vector<DirichletNode> hostBcs;

        const auto& vertices = mesh.getHostVertices();

        hostBcs.reserve(0.1 * vertices.size());

        for (unsigned i = 0; i < vertices.size(); ++i) {
            const Point2& node = vertices[i];

            if (std::fabs(node.x - (-1.0)) < CONSTANTS::DOUBLE_MIN)
                hostBcs.push_back({ i, -1.0 });
            else if (std::fabs(node.x - 1.0) < CONSTANTS::DOUBLE_MIN)
                hostBcs.push_back({ i, 1.0 });
            else if (std::fabs(node.y) < CONSTANTS::DOUBLE_MIN)
                hostBcs.push_back({ i, 0.0 });
            else if (std::fabs(node.y - 1.0) < CONSTANTS::DOUBLE_MIN)
                hostBcs.push_back({ i, 2.0 });
        }

        bcs.setupDirichletBCs(hostBcs);
    }

    timer.stop("Boundary conditions setup");

    SparseMatrixCSR matrix(mesh);
    NumericalIntegrator2D integrator(mesh, qf2D3);

    deviceVector<double> rhsVector;
    rhsVector.allocate(problemSize);
    zero_value_device(rhsVector.data, problemSize);

    timer.start();

    integrator.assembleSystem(matrix, rhsVector);
    bcs.applyBCs(matrix, rhsVector);

    timer.stop("Assembly of system and rhs");

    matrix.exportMatrix("matrix.dat");

    deviceVector<double> solution;
    solution.allocate(problemSize);

    timer.start();

    SolverCG cgSolver(1e-8, 1000);
    cgSolver.init(matrix, true);
    cgSolver.solve(matrix, solution, rhsVector);

    timer.stop("PCG solver");
    timer.start();

    SolverGMRES gmresSolver(1e-8, 1000);
    gmresSolver.init(matrix, true);
    gmresSolver.solve(matrix, solution, rhsVector);

    timer.stop("GMRES solver");

    solution.exportToFile("solution.dat");
    rhsVector.exportToFile("rhs.dat");

    DataExport dataExport(mesh);
    dataExport.addScalarDataVector(solution, "solution");
    dataExport.exportToVTK("solution.vtu");

    return EXIT_SUCCESS;
}
